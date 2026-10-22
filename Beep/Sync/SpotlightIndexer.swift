import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Makes courses and files findable from iOS Spotlight. Identifiers: "course:<id>", "file:<key>".
///
/// The index is built from `Entries`, a snapshot of plain values taken on the IndexActor (the same
/// context that inserts and deletes files, so the two never overlap). The indexing task itself never
/// touches SwiftData: a background sync may be suspended with it half-way and resumed hours later,
/// after the next sync has deleted rows. TestFlight 0.2.0 (16) crashed exactly there, faulting a
/// deleted FileItem from a detached task (`_InvalidFutureBackingData`).
nonisolated enum SpotlightIndexer {
    static let courseDomain = "com.mattiacolombo.Beep.course"
    static let fileDomain = "com.mattiacolombo.Beep.file"

    struct CourseEntry: Sendable, Equatable {
        let id: Int
        let title: String
        let description: String
        let keywords: [String]
    }

    struct FileEntry: Sendable, Equatable {
        let key: String
        let filename: String
        let fileExtension: String
        let description: String
        let courseTitle: String
        let keywords: [String]
        let modified: Date
    }

    struct Entries: Sendable, Equatable {
        var courses: [CourseEntry] = []
        var files: [FileEntry] = []
    }

    static func items(from entries: Entries) -> [CSSearchableItem] {
        var items: [CSSearchableItem] = []
        items.reserveCapacity(entries.courses.count + entries.files.count)
        for c in entries.courses {
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = c.title
            a.contentDescription = c.description
            a.keywords = c.keywords
            a.identifier = "course:\(c.id)"
            items.append(CSSearchableItem(uniqueIdentifier: "course:\(c.id)", domainIdentifier: courseDomain, attributeSet: a))
        }
        for f in entries.files {
            let type = f.fileExtension.isEmpty ? nil : UTType(filenameExtension: f.fileExtension)
            let fa = CSSearchableItemAttributeSet(contentType: type ?? .data)
            fa.title = f.filename
            fa.contentDescription = f.description
            fa.keywords = f.keywords
            fa.contentModificationDate = f.modified
            items.append(CSSearchableItem(uniqueIdentifier: "file:\(f.key)", domainIdentifier: fileDomain, attributeSet: fa))
        }
        return items
    }

    /// Replaces the whole index with `entries`. Safe to suspend, resume or cancel at any point.
    static func reindex(entries: Entries) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let items = items(from: entries)
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [courseDomain, fileDomain])
        // Batches keep memory flat for thousands of files.
        for chunk in stride(from: 0, to: items.count, by: 500).map({ Array(items[$0..<min($0 + 500, items.count)]) }) {
            if Task.isCancelled { return }
            try? await index.indexSearchableItems(chunk)
        }
    }

    static func destination(for activity: NSUserActivity) -> AppRouter.Destination? {
        guard activity.activityType == CSSearchableItemActionType,
              let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return nil }
        if id.hasPrefix("course:"), let n = Int(id.dropFirst(7)) { return .course(n) }
        if id.hasPrefix("file:") { return .file(String(id.dropFirst(5))) }
        return nil
    }
}
