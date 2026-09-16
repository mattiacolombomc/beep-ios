import Foundation
import SwiftData

/// Background home of the Indexer: parses and upserts course contents on its own
/// ModelContext so a full sync (tens of courses, thousands of files) never blocks
/// the main thread. Returns plain values; the main actor re-fetches what it needs.
@ModelActor
actor IndexActor {
    struct CourseRef: Sendable, Equatable {
        let id: Int
        let title: String
    }

    struct ContentResult: Sendable {
        let title: String
        let isFirstIndex: Bool
        let diff: Indexer.ContentDiff
        /// Keys of files to download now (auto-download courses only).
        let wantedKeys: [String]
    }

    private var indexer: Indexer { Indexer(context: modelContext) }

    func upsertCourses(_ dtos: [CourseDTO], categories: [CategoryDTO]) throws {
        // Auto-download is opt-in: nothing is downloaded until the user enables a course.
        try indexer.upsertCourses(dtos, categories: categories) { _, _ in false }
    }

    /// Courses to index: one course, or every non-archived course.
    func targets(only courseID: Int?) throws -> [CourseRef] {
        var descriptor = FetchDescriptor<Course>(sortBy: [SortDescriptor(\.title)])
        if let courseID { descriptor.predicate = #Predicate { $0.id == courseID } }
        return try modelContext.fetch(descriptor)
            .filter { courseID != nil || !$0.isArchived }
            .map { CourseRef(id: $0.id, title: $0.title) }
    }

    func upsertContents(_ sections: [SectionDTO], courseID: Int, token: String) throws -> ContentResult? {
        let descriptor = FetchDescriptor<Course>(predicate: #Predicate { $0.id == courseID })
        guard let course = try modelContext.fetch(descriptor).first else { return nil }
        let isFirstIndex = course.lastIndexedAt == nil
        let diff = try indexer.upsertContents(sections, for: course, token: token)
        let wanted = course.syncEnabled ? course.files.filter { !$0.isDownloaded || $0.hasUpdate }.map(\.key) : []
        return ContentResult(title: course.title, isFirstIndex: isFirstIndex, diff: diff, wantedKeys: wanted)
    }

    func upsertNotifications(_ dtos: [NotificationDTO]) throws -> Int {
        try indexer.upsertNotifications(dtos)
    }
}
