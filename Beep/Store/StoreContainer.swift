import Foundation
import SwiftData

enum StoreContainer {
    static let appGroup = "group.com.mattiacolombo.Beep"
    static let schema = Schema([Course.self, CourseSection.self, CourseModule.self, FileItem.self, WebeepNotification.self])

    /// Shared store in the App Group so the widget can read it. Falls back to the
    /// app's own Application Support when the group container is unavailable.
    static var storeURL: URL {
        #if os(macOS)
        // No widget on the Mac: the store lives in the app's own sandbox container.
        let base = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        #else
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? URL.applicationSupportDirectory
        #endif
        return base.appending(path: "Beep.store")
    }

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        if inMemory {
            return try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        }
        migrateLegacyStoreIfNeeded()
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Early builds kept the store in Application Support/default.store.
    private static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        let legacy = URL.applicationSupportDirectory.appending(path: "default.store")
        guard fm.fileExists(atPath: legacy.path(percentEncoded: false)),
              !fm.fileExists(atPath: storeURL.path(percentEncoded: false)) else { return }
        try? fm.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let from = legacy.appendingPathExtension(suffix.isEmpty ? "" : "").deletingPathExtension().appendingPathExtension("store" + suffix)
            let src = URL(fileURLWithPath: legacy.path(percentEncoded: false) + suffix)
            let dst = URL(fileURLWithPath: storeURL.path(percentEncoded: false) + suffix)
            _ = from
            if fm.fileExists(atPath: src.path(percentEncoded: false)) { try? fm.moveItem(at: src, to: dst) }
        }
    }
}
