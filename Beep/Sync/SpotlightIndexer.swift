import CoreSpotlight
import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Makes courses and files findable from iOS Spotlight. Identifiers: "course:<id>", "file:<key>".
enum SpotlightIndexer {
    static let courseDomain = "com.mattiacolombo.Beep.course"
    static let fileDomain = "com.mattiacolombo.Beep.file"

    @MainActor
    static func reindex(context: ModelContext) async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let courses = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        var items: [CSSearchableItem] = []
        for c in courses where !c.isArchived {
            let a = CSSearchableItemAttributeSet(contentType: .content)
            a.title = c.title
            a.contentDescription = [c.code, c.professors, c.categoryName].compactMap { $0 }.joined(separator: " · ")
            a.keywords = [c.monogram, c.code, c.categoryName].compactMap { $0 }
            a.identifier = "course:\(c.id)"
            items.append(CSSearchableItem(uniqueIdentifier: "course:\(c.id)", domainIdentifier: courseDomain, attributeSet: a))
            for f in c.files {
                let fa = CSSearchableItemAttributeSet(contentType: UTType(filenameExtension: f.fileExtension) ?? .data)
                fa.title = f.filename
                fa.contentDescription = [c.title, f.module?.name].compactMap { $0 }.joined(separator: " › ")
                fa.keywords = [c.monogram, c.title]
                fa.contentModificationDate = f.timemodified
                items.append(CSSearchableItem(uniqueIdentifier: "file:\(f.key)", domainIdentifier: fileDomain, attributeSet: fa))
            }
        }
        let index = CSSearchableIndex.default()
        try? await index.deleteSearchableItems(withDomainIdentifiers: [courseDomain, fileDomain])
        // Batches keep memory flat for thousands of files.
        for chunk in stride(from: 0, to: items.count, by: 500).map({ Array(items[$0..<min($0 + 500, items.count)]) }) {
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
