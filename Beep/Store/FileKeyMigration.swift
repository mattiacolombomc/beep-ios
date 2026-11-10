import Foundation
import SwiftData
import os

/// One-time rewrite of the stored file keys to the revision-free form of `FileURLTokenizer.key`.
///
/// Without it the first sync after the update would find none of the stored keys, delete every
/// file and index them all again as new (and download them again in auto-download courses).
enum FileKeyMigration {
    static let version = 2
    static let defaultsKey = "store.fileKeyVersion"
    private static let log = Logger(subsystem: "com.mattiacolombo.Beep", category: "store")

    /// Runs before anything reads the store. Only the apps call it: the widget and the intents
    /// open the same store but must never write to it.
    @MainActor
    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: defaultsKey) < version else { return }
        do {
            let result = try run(in: context)
            defaults.set(version, forKey: defaultsKey)
            log.notice("file keys migrated: \(result.renamed, privacy: .public) renamed, \(result.dropped, privacy: .public) duplicates dropped")
        } catch {
            // Left unmarked: it is retried at the next launch.
            context.rollback()
            log.error("file key migration failed: \(String(describing: error), privacy: .public)")
        }
    }

    @discardableResult
    static func run(in context: ModelContext) throws -> (renamed: Int, dropped: Int) {
        let files = try context.fetch(FetchDescriptor<FileItem>())
        var groups: [String: [FileItem]] = [:]
        for file in files { groups[FileURLTokenizer.key(file.key), default: []].append(file) }

        // Rows that would end up with the same key: keep the downloaded one, else the oldest.
        var keepers: [(key: String, file: FileItem)] = []
        var dropped = 0
        for (key, group) in groups {
            let keeper = group.min { a, b in
                if a.isDownloaded != b.isDownloaded { return a.isDownloaded }
                return a.firstSeenAt < b.firstSeenAt
            }!
            if group.count > 1 {
                keeper.firstSeenAt = group.map(\.firstSeenAt).min() ?? keeper.firstSeenAt
                for file in group where file !== keeper {
                    context.delete(file)
                    dropped += 1
                }
            }
            keepers.append((key, keeper))
        }
        // The key is unique: the duplicates must be gone from the store before a keeper takes it.
        if dropped > 0 { try context.save() }

        var renamed = 0
        for (key, file) in keepers where file.key != key {
            file.key = key
            renamed += 1
        }
        if context.hasChanges { try context.save() }
        return (renamed, dropped)
    }
}
