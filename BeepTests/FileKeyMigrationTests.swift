import Foundation
import SwiftData
import Testing
@testable import Beep

@MainActor
struct FileKeyMigrationTests {
    let container: ModelContainer
    let context: ModelContext
    let base = "https://webeep.polimi.it/webservice/pluginfile.php"

    init() throws {
        container = try StoreContainer.make(inMemory: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private func insert(_ key: String, seen: TimeInterval, downloaded: Bool = false) -> FileItem {
        let f = FileItem(key: key, filename: (key as NSString).lastPathComponent, filepath: "/", filesize: 1,
                         timemodified: Date(timeIntervalSince1970: 10), mimetype: nil, remoteURL: key + "&token=T",
                         firstSeenAt: Date(timeIntervalSince1970: seen))
        if downloaded {
            f.state = .downloaded
            f.localRelativePath = "Course/\(f.filename)"
            f.downloadedTimemodified = f.timemodified
        }
        context.insert(f)
        return f
    }

    @Test func storedKeysLoseTheRevisionAndKeepTheirState() throws {
        let a = insert("\(base)/5/mod_folder/content/19/a.pdf?forcedownload=1", seen: 100, downloaded: true)
        let b = insert("\(base)/6/mod_resource/content/28/b.pdf?forcedownload=1", seen: 200)
        let page = insert("\(base)/7/mod_page/content/index.html?forcedownload=1", seen: 300)
        try context.save()

        let result = try FileKeyMigration.run(in: context)

        #expect(result.renamed == 2)
        #expect(result.dropped == 0)
        #expect(a.key == "\(base)/5/mod_folder/content/0/a.pdf?forcedownload=1")
        #expect(b.key == "\(base)/6/mod_resource/content/0/b.pdf?forcedownload=1")
        #expect(page.key == "\(base)/7/mod_page/content/index.html?forcedownload=1")
        #expect(a.isDownloaded && a.localRelativePath == "Course/\(a.filename)")
        #expect(a.firstSeenAt == Date(timeIntervalSince1970: 100))
        #expect(a.remoteURL.contains("/content/19/"))
        #expect(try context.fetchCount(FetchDescriptor<FileItem>()) == 3)

        // Running it again finds nothing to do.
        let again = try FileKeyMigration.run(in: context)
        #expect(again.renamed == 0 && again.dropped == 0)
    }

    /// Two rows for the same file under two revisions: one survives, the downloaded one,
    /// with the oldest first-seen date so it does not turn "new".
    @Test func duplicatesCollapseOntoTheDownloadedRow() throws {
        _ = insert("\(base)/5/mod_folder/content/19/a.pdf?forcedownload=1", seen: 100)
        let kept = insert("\(base)/5/mod_folder/content/20/a.pdf?forcedownload=1", seen: 900, downloaded: true)
        try context.save()

        let result = try FileKeyMigration.run(in: context)

        #expect(result.dropped == 1)
        let all = try context.fetch(FetchDescriptor<FileItem>())
        #expect(all.count == 1)
        #expect(all.first?.persistentModelID == kept.persistentModelID)
        #expect(kept.key == "\(base)/5/mod_folder/content/0/a.pdf?forcedownload=1")
        #expect(kept.isDownloaded)
        #expect(kept.firstSeenAt == Date(timeIntervalSince1970: 100))
    }

    @Test func itRunsOncePerStore() throws {
        let defaults = try #require(UserDefaults(suiteName: "FileKeyMigrationTests"))
        defaults.removePersistentDomain(forName: "FileKeyMigrationTests")
        let f = insert("\(base)/5/mod_folder/content/19/a.pdf", seen: 1)
        try context.save()

        FileKeyMigration.runIfNeeded(in: context, defaults: defaults)
        #expect(f.key.contains("/content/0/"))
        #expect(defaults.integer(forKey: FileKeyMigration.defaultsKey) == FileKeyMigration.version)
    }
}
