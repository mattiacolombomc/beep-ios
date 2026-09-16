import Foundation
import Observation
import SwiftData

/// Orchestrates index refreshes (courses + contents). Downloads are handled by
/// `DownloadManager` (M2). Main-actor bound like the SwiftData models it touches.
@Observable
final class SyncEngine {
    enum Phase: Equatable {
        case idle
        case indexing(done: Int, total: Int, current: String?)
        case failed(String)
    }

    struct Report: Equatable {
        var coursesIndexed = 0
        var newFiles = 0
        var updatedFiles = 0
        var errors: [String] = []
        var finishedAt = Date.now
    }

    private(set) var phase: Phase = .idle
    private(set) var lastReport: Report?
    private(set) var lastSyncAt: Date? {
        didSet { UserDefaults.standard.set(lastSyncAt, forKey: "lastSyncAt") }
    }

    private let context: ModelContext
    private var running: Task<Report, Never>?

    init(context: ModelContext) {
        self.context = context
        lastSyncAt = UserDefaults.standard.object(forKey: "lastSyncAt") as? Date
    }

    var isRunning: Bool { running != nil }

    /// Refreshes the course list and every course's contents. Coalesces concurrent calls.
    @discardableResult
    func syncAll(client: MoodleClient, userID: Int) async -> Report {
        if let running { return await running.value }
        let task = Task { await run(client: client, userID: userID, only: nil) }
        running = task
        let report = await task.value
        running = nil
        return report
    }

    @discardableResult
    func sync(course: Course, client: MoodleClient) async -> Report {
        if let running { return await running.value }
        let task = Task { await run(client: client, userID: nil, only: course.id) }
        running = task
        let report = await task.value
        running = nil
        return report
    }

    private func run(client: MoodleClient, userID: Int?, only courseID: Int?) async -> Report {
        var report = Report()
        let indexer = Indexer(context: context)
        do {
            if let userID {
                async let coursesTask = client.userCourses(userID: userID)
                async let categoriesTask = client.categories()
                let (courses, categories) = try await (coursesTask, categoriesTask)
                try indexer.upsertCourses(courses, categories: categories) { _, category in AcademicYear.isCurrent(category) }
            }
            var descriptor = FetchDescriptor<Course>()
            if let courseID { descriptor.predicate = #Predicate { $0.id == courseID } }
            let targets = try context.fetch(descriptor)
            phase = .indexing(done: 0, total: targets.count, current: targets.first?.title)

            // Fetch contents 4 at a time; apply to the store on the main actor as they arrive.
            var done = 0
            var iterator = targets.makeIterator()
            var inFlight: [Int: Task<[SectionDTO], Error>] = [:]
            func launch(_ c: Course) { inFlight[c.id] = Task { try await client.courseContents(courseID: c.id) } }
            for _ in 0..<4 { if let c = iterator.next() { launch(c) } }
            let byID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
            while !inFlight.isEmpty {
                // Wait for any: cheap approach, iterate over in-flight tasks in order.
                guard let (id, task) = inFlight.first else { break }
                inFlight.removeValue(forKey: id)
                do {
                    let sections = try await task.value
                    if let course = byID[id] {
                        let diff = try indexer.upsertContents(sections, for: course, token: client.token)
                        report.newFiles += diff.newFiles.count
                        report.updatedFiles += diff.updatedFiles.count
                        report.coursesIndexed += 1
                    }
                } catch MoodleError.invalidToken {
                    throw MoodleError.invalidToken
                } catch {
                    report.errors.append("\(byID[id]?.title ?? "\(id)"): \(error)")
                }
                done += 1
                if let c = iterator.next() { launch(c) }
                phase = .indexing(done: done, total: targets.count, current: inFlight.keys.compactMap { byID[$0]?.title }.first)
            }
            lastSyncAt = .now
            phase = .idle
        } catch {
            report.errors.append(String(describing: error))
            phase = .failed(String(describing: error))
        }
        report.finishedAt = .now
        lastReport = report
        return report
    }
}
