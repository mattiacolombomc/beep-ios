import AppIntents
import Foundation
import SwiftData

/// "Sync Beep" – refreshes courses and queues downloads, no UI needed.
struct SyncNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Sync WeBeep courses"
    static let description = IntentDescription("Checks WeBeep for new material and downloads it for your auto-download courses.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let session = AppServices.session, let sync = AppServices.sync,
              let client = session.client, let user = session.user, user.id != 0 else {
            return .result(dialog: "Open Beep and sign in to WeBeep first.")
        }
        let report = await sync.syncAll(client: client, userID: user.id, trigger: .manual)
        let news = report.newFiles + report.updatedFiles
        let dialog: IntentDialog = news == 0
            ? "Everything is up to date."
            : "\(news) new files across \(report.coursesWithNews.count) courses. Downloading now."
        return .result(dialog: dialog)
    }
}

/// A course, as Shortcuts/Siri sees it.
struct CourseEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Course")
    static let defaultQuery = CourseQuery()

    let id: Int
    let title: String
    let code: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: code.map { "\($0)" })
    }
}

struct CourseQuery: EntityQuery {
    @MainActor
    private func all() -> [CourseEntity] {
        guard let container = try? StoreContainer.make() else { return [] }
        let ctx = ModelContext(container)
        let courses = (try? ctx.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.title)]))) ?? []
        return courses.filter { !$0.isArchived }.map { CourseEntity(id: $0.id, title: $0.title, code: $0.code) }
    }

    func entities(for identifiers: [Int]) async throws -> [CourseEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CourseEntity] {
        await all()
    }
}

extension CourseQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [CourseEntity] {
        let q = string.lowercased()
        return await all().filter { $0.title.lowercased().contains(q) || ($0.code?.contains(q) ?? false) || CourseMonogram.make($0.title).lowercased() == q }
    }
}

/// "Open FLC in Beep"
struct OpenCourseIntent: AppIntent {
    static let title: LocalizedStringResource = "Open course"
    static let description = IntentDescription("Opens a course in Beep.")
    static let openAppWhenRun = true

    @Parameter(title: "Course")
    var course: CourseEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$course) in Beep")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppServices.router?.open(.course(course.id))
        return .result()
    }
}

struct BeepShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SyncNowIntent(),
                    phrases: ["Sync \(.applicationName)", "Sincronizza \(.applicationName)", "Check WeBeep with \(.applicationName)"],
                    shortTitle: "Sync now",
                    systemImageName: "arrow.triangle.2.circlepath")
        AppShortcut(intent: OpenCourseIntent(),
                    phrases: ["Open a course in \(.applicationName)", "Apri un corso in \(.applicationName)"],
                    shortTitle: "Open course",
                    systemImageName: "graduationcap")
    }
}
