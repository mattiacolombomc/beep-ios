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

    private(set) var phase: Phase = .idle {
        didSet {
            let indexing = if case .indexing = phase { true } else { false }
            if indexing != isIndexing { isIndexing = indexing }
        }
    }
    /// Changes only when indexing starts or ends, unlike `phase` (once per course): views that
    /// only need "is a sync running" read this and are not re-rendered 56 times per sync.
    private(set) var isIndexing = false
    private(set) var lastReport: Report?
    private(set) var lastSyncAt: Date? {
        didSet {
            UserDefaults.standard.set(lastSyncAt, forKey: "lastSyncAt")
            UserDefaults(suiteName: StoreContainer.appGroup)?.set(lastSyncAt, forKey: "lastSyncAt")
        }
    }

    let downloads: DownloadManager
    /// Teaching periods from the Polimi catalogue, refreshed after each full sync.
    let semesters: SemesterResolver
    /// Start years of the academic years the courses belong to, newest first; the filter menu
    /// lists them. Changes only when a year appears or goes, so observers are rarely re-rendered.
    private(set) var academicYears: [Int] = []
    /// WeBeep rejected the token during a sync.
    var onInvalidToken: ((Trigger) -> Void)?
    /// Main context: the download queue reads from it.
    private let context: ModelContext
    /// Created off the main thread: a SwiftData `ModelActor` initialized on the main thread runs
    /// its work there, which made the whole sync (parsing and upserting every course) block the UI.
    private let storeTask: Task<IndexActor, Never>
    private var running: Task<Report, Never>?
    /// Spotlight rebuild of the last sync; cancelled when the next one starts to index.
    private var spotlightTask: Task<Void, Never>?

    init(container: ModelContainer, downloads: DownloadManager) {
        self.context = container.mainContext
        self.storeTask = Task.detached(priority: .userInitiated) { IndexActor(modelContainer: container) }
        self.downloads = downloads
        self.semesters = SemesterResolver(context: container.mainContext)
        lastSyncAt = UserDefaults.standard.object(forKey: "lastSyncAt") as? Date
    }

    var isRunning: Bool { running != nil }

    func refreshYears() {
        let courses = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        let years = Set(courses.compactMap { AcademicYear.startYear($0.categoryName) }).sorted(by: >)
        if years != academicYears { academicYears = years }
    }

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
            let store = await storeTask.value
            if let userID {
                async let coursesTask = client.userCourses(userID: userID)
                async let categoriesTask = client.categories()
                let (courses, categories) = try await (coursesTask, categoriesTask)
                try await store.upsertCourses(courses, categories: categories)
                // Edition folders may have changed (a new section of a course in the same year).
                _ = downloads.local.migrateLayout(courses: try context.fetch(FetchDescriptor<Course>()))
                refreshYears()
            }
            let targets = try await store.targets(only: courseID)
            phase = .indexing(done: 0, total: targets.count, current: targets.first?.title)

            var done = 0
            // Each save merges into the main context and every list re-fetches and re-renders:
            // save at most every couple of seconds instead of once per course.
            var lastSave = Date.now
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
                    if let result = try await store.upsertContents(sections, courseID: id, token: client.token, save: false) {
                        report.coursesIndexed += 1
                        // A course indexed for the first time is a baseline, not news:
                        // its files must never trigger badges or notifications.
                        if !result.isFirstIndex {
                            report.newFiles += result.diff.newFiles.count
                            report.updatedFiles += result.diff.updatedFiles.count
                            if !result.diff.newFiles.isEmpty || !result.diff.updatedFiles.isEmpty { report.coursesWithNews.append(result.title) }
                        }
                        if !result.wantedKeys.isEmpty {
                            // The download queue fetches the files on the main context: they must be saved.
                            try await store.save()
                            lastSave = .now
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
                if Date.now.timeIntervalSince(lastSave) > 2 {
                    try? await store.save()
                    lastSave = .now
                }
                if let c = iterator.next() { launch(c) }
                phase = .indexing(done: done, total: targets.count, current: inFlight.keys.compactMap { byID[$0]?.title }.first)
            }
            try? await store.save()
            if let userID, let dto = try? await client.popupNotifications(userID: userID) {
                report.newAnnouncements = (try? await store.upsertNotifications(dto.notifications)) ?? 0
            }
            lastSyncAt = .now
            phase = .idle
            if userID != nil {
                // Snapshot on the store actor (serialised with its deletes), index from plain values:
                // the detached task holds no model, so a background suspension can't leave it with
                // faults that the next sync invalidates (crash in 0.2.0 (16)).
                spotlightTask?.cancel()
                if let entries = try? await store.spotlightEntries() {
                    spotlightTask = Task.detached(priority: .utility) { await SpotlightIndexer.reindex(entries: entries) }
                }
                semesters.resolveDue()
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch MoodleError.invalidToken {
            report.errors.append("invalidToken")
            phase = .failed(String(localized: "Session expired"))
            onInvalidToken?(trigger)
        } catch {
            report.errors.append(String(describing: error))
            phase = .failed(error.localizedDescription)
        }
        report.finishedAt = .now
        lastReport = report
        // Local notifications: only for background checks, only after onboarding's first full sync.
        if trigger == .background,
           UserDefaults.standard.bool(forKey: "settings.notifications"),
           UserDefaults.standard.bool(forKey: "onboarding.done") {
            Notifier.notifySyncResults(newFiles: report.newFiles + report.updatedFiles, courses: report.coursesWithNews, newAnnouncements: report.newAnnouncements)
        }
        #if os(iOS)
        if UserDefaults.standard.bool(forKey: "settings.backgroundRefresh") { BackgroundRefresh.schedule() }
        #else
        MacSyncScheduler.shared?.reschedule()
        #endif
        return report
    }

    /// Main-context models for keys the background indexer just wrote.
    private func files(withKeys keys: [String]) throws -> [FileItem] {
        let descriptor = FetchDescriptor<FileItem>(predicate: #Predicate { keys.contains($0.key) })
        return try context.fetch(descriptor)
    }
}
