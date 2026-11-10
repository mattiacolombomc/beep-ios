import Foundation
import SwiftData
import os

/// How the files a teacher removed from WeBeep are shown.
enum RemovedDisplay: String, CaseIterable, Identifiable, Sendable {
    /// A closed "Removed from WeBeep" group at the bottom of the folder or section.
    case grouped
    /// Where they were, labelled.
    case inline
    case hidden
    var id: Self { self }
}

/// What happens to content that is gone from WeBeep.
///
/// The sync never deletes a row while the app runs: it only sets `removedAt` (see `Indexer`).
/// Here the downloaded files become keepsakes (renamed on disk, key freed for a future file with
/// the same name), and everything else is deleted at launch, before any view holds it.
@MainActor
enum RemovedContent {
    static let keepKey = "settings.removedFiles.keep"
    static let displayKey = "settings.removedFiles.display"
    /// Appended to the key of a kept file, with the removal time.
    static let marker = "#removed-"
    private static let log = Logger(subsystem: "com.mattiacolombo.Beep", category: "store")

    static var keeps: Bool { UserDefaults.standard.object(forKey: keepKey) as? Bool ?? true }

    /// Renames on disk the downloaded files that were just marked as removed and frees their key.
    /// Runs right after the sync saves a removal, before any download of the same course starts.
    @discardableResult
    static func settle(in context: ModelContext, local: LocalFiles, keep: Bool = keeps,
                       label: String = String(localized: "removed", comment: "Prefix of the name on disk of a file removed from WeBeep: [removed 2026-11-10] slides.pdf"),
                       timeZone: TimeZone = .current) throws -> Int {
        guard keep else { return 0 }
        let downloaded = FileState.downloaded.rawValue
        let pending = try context.fetch(FetchDescriptor<FileItem>(predicate: #Predicate { $0.removedAt != nil && $0.stateRaw == downloaded }))
            .filter { !$0.key.contains(marker) }
        var settled = 0
        for file in pending {
            guard let removedAt = file.removedAt else { continue }
            guard local.markRemoved(file, label: label, on: removedAt, timeZone: timeZone) else {
                // No local copy after all: nothing to keep, it goes at the next launch.
                file.state = .notDownloaded
                file.localRelativePath = nil
                continue
            }
            file.key = try freeKey(file.key + marker + String(Int(removedAt.timeIntervalSince1970)), in: context)
            settled += 1
        }
        if context.hasChanges { try context.save() }
        if settled > 0 { log.notice("kept \(settled, privacy: .public) files removed from WeBeep") }
        return settled
    }

    private static func freeKey(_ wanted: String, in context: ModelContext) throws -> String {
        var key = wanted
        var n = 1
        while try context.fetchCount(FetchDescriptor<FileItem>(predicate: #Predicate { $0.key == key })) > 0 {
            n += 1
            key = "\(wanted)-\(n)"
        }
        return key
    }

    /// Deletes what is marked as removed and not kept. Only at launch.
    static func purge(in context: ModelContext, keep: Bool = keeps) throws {
        var files = 0, modules = 0, sections = 0
        for file in try context.fetch(FetchDescriptor<FileItem>(predicate: #Predicate { $0.removedAt != nil })) where !(keep && file.isDownloaded) {
            context.delete(file)
            files += 1
        }
        if files > 0 { try context.save() }
        for module in try context.fetch(FetchDescriptor<CourseModule>(predicate: #Predicate { $0.removedAt != nil })) where module.files.isEmpty {
            context.delete(module)
            modules += 1
        }
        if modules > 0 { try context.save() }
        for section in try context.fetch(FetchDescriptor<CourseSection>(predicate: #Predicate { $0.removedAt != nil })) where section.modules.isEmpty {
            context.delete(section)
            sections += 1
        }
        if sections > 0 { try context.save() }
        if files + modules + sections > 0 {
            log.notice("purged removed content: \(files, privacy: .public) files, \(modules, privacy: .public) modules, \(sections, privacy: .public) sections")
        }
    }

    /// At launch, before any view reads the store.
    static func cleanUpAtLaunch(in context: ModelContext, local: LocalFiles) {
        do {
            try settle(in: context, local: local)
            try purge(in: context)
        } catch {
            context.rollback()
            log.error("removed content clean-up failed: \(String(describing: error), privacy: .public)")
        }
    }
}
