import Foundation
import Observation
import SwiftData
import WidgetKit

/// Orchestrates index refreshes (courses + contents) and hands new files to the
/// DownloadManager for courses with auto-download on. Network and UI state live
/// here on the main actor; the store writes happen in `IndexActor`.
@Observable
final class SyncEngine {
    enum Phase: Equatable {
        case idle
        case indexing(done: Int, total: Int, current: String?)
        case failed(String)
    }

    enum Trigger: Equatable { case manual, launch, background }

    struct Report: Equatable {
        var coursesIndexed = 0
        var newFiles = 0
        var updatedFiles = 0
        var queuedDownloads = 0
        var newAnnouncements = 0
        var coursesWithNews: [String] = []
        var errors: [String] = []
        var finishedAt = Date.now
    }

    private(set) var phase: Phase = .idle
    private(set) var lastReport: Report?
    private(set) var lastSyncAt: Date? {
        didSet {
            UserDefaults.standard.set(lastSyncAt, forKey: "lastSyncAt")
            UserDefaults(suiteName: StoreContainer.appGroup)?.set(lastSyncAt, forKey: "lastSyncAt")
        }
    }

    let downloads: DownloadManager
    /// WeBeep rejected the token during a sync.
    var onInvalidToken: ((Trigger) -> Void)?
    /// Main context: download queue and Spotlight read from it.
    private let context: ModelContext
    private let store: IndexActor
    private var running: Task<Report, Never>?

    init(container: ModelContainer, downloads: DownloadManager) {
        self.context = container.mainContext
        self.store = IndexActor(modelContainer: container)
        self.downloads = downloads
        lastSyncAt = UserDefaults.standard.object(forKey: "lastSyncAt") as? Date
    }

    var isRunning: Bool { running != nil }

    /// Refreshes the course list and every course's contents. Coalesces concurrent calls.
    @discardableResult
    func syncAll(client: MoodleClient, userID: Int, trigger: Trigger = .manual) async -> Report {
        if DemoData.isEnabled { lastSyncAt = .now; return Report() }
        if let running { return await running.value }
        let task = Task { await run(client: client, userID: userID, only: nil, trigger: trigger) }
        running = task
        let report = await task.value
        running = nil
        return report
    }

    @discardableResult
    func sync(course: Course, client: MoodleClient) async -> Report {
        if DemoData.isEnabled { return Report() }
        if let running { return await running.value }
        let task = Task { await run(client: client, userID: nil, only: course.id, trigger: .manual) }
        running = task
        let report = await task.value
        running = nil
        return report
    }

    /// Queue every missing/outdated file of a course (or of a subset of files).
    func downloadAll(of course: Course) {
        downloads.enqueue(course.files)
    }

    private func run(client: MoodleClient, userID: Int?, only courseID: Int?, trigger: Trigger) async -> Report {
        var report = Report()
        downloads.resetSessionCounters()
        if trigger != .background { downloads.flushDeferred() }
        do {
            if let userID {
                async let coursesTask = client.userCourses(userID: userID)
                async let categoriesTask = client.categories()
                let (courses, categories) = try await (coursesTask, categoriesTask)
                try await store.upsertCourses(courses, categories: categories)
            }
            let targets = try await store.targets(only: courseID)
            phase = .indexing(done: 0, total: targets.count, current: targets.first?.title)

            var done = 0
            var iterator = targets.makeIterator()
            var inFlight: [Int: Task<[SectionDTO], Error>] = [:]
            func launch(_ c: IndexActor.CourseRef) { inFlight[c.id] = Task { try await client.courseContents(courseID: c.id) } }
            for _ in 0..<4 { if let c = iterator.next() { launch(c) } }
            let byID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
            while !inFlight.isEmpty {
                guard let (id, task) = inFlight.first else { break }
                inFlight.removeValue(forKey: id)
                do {
                    let sections = try await task.value
                    if let result = try await store.upsertContents(sections, courseID: id, token: client.token) {
                        report.coursesIndexed += 1
                        // A course indexed for the first time is a baseline, not news:
                        // its files must never trigger badges or notifications.
                        if !result.isFirstIndex {
                            report.newFiles += result.diff.newFiles.count
                            report.updatedFiles += result.diff.updatedFiles.count
                            if !result.diff.newFiles.isEmpty || !result.diff.updatedFiles.isEmpty { report.coursesWithNews.append(result.title) }
                        }
                        if !result.wantedKeys.isEmpty {
                            let wanted = try files(withKeys: result.wantedKeys)
                            downloads.enqueue(wanted, background: trigger == .background)
                            report.queuedDownloads += wanted.count
                        }
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
            if let userID, let dto = try? await client.popupNotifications(userID: userID) {
                report.newAnnouncements = (try? await store.upsertNotifications(dto.notifications)) ?? 0
            }
            lastSyncAt = .now
            phase = .idle
            if userID != nil { Task { await SpotlightIndexer.reindex(context: context) } }
            WidgetCenter.shared.reloadAllTimelines()
        } catch MoodleError.invalidToken {
            report.errors.append("invalidToken")
            phase = .failed(String(localized: "Session expired"))
            onInvalidToken?(trigger)
        } catch {
            report.errors.append(String(describing: error))
            phase = .failed(String(describing: error))
        }
        report.finishedAt = .now
        lastReport = report
        // Local notifications: only for background checks, only after onboarding's first full sync.
        if trigger == .background,
           UserDefaults.standard.bool(forKey: "settings.notifications"),
           UserDefaults.standard.bool(forKey: "onboarding.done") {
            Notifier.notifySyncResults(newFiles: report.newFiles + report.updatedFiles, courses: report.coursesWithNews, newAnnouncements: report.newAnnouncements)
        }
        if UserDefaults.standard.bool(forKey: "settings.backgroundRefresh") { BackgroundRefresh.schedule() }
        return report
    }

    /// Main-context models for keys the background indexer just wrote.
    private func files(withKeys keys: [String]) throws -> [FileItem] {
        let descriptor = FetchDescriptor<FileItem>(predicate: #Predicate { keys.contains($0.key) })
        return try context.fetch(descriptor)
    }
}
