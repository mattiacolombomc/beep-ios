import Foundation
import SwiftData
import Testing
@testable import Beep

@MainActor
struct RemovedContentTests {
    let container: ModelContainer
    let context: ModelContext
    let root: URL
    let local: LocalFiles
    let course: Course
    let folder: CourseModule
    /// 2026-11-10 12:00 UTC.
    let removal = Date(timeIntervalSince1970: 1_794_312_000)

    init() throws {
        container = try StoreContainer.make(inMemory: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
        root = FileManager.default.temporaryDirectory.appending(path: "beep-removed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        local = LocalFiles(root: root)
        course = Course(id: 1, fullname: "", displayName: "", title: "FLC", code: nil, professors: nil,
                        categoryID: 0, categoryName: "2026-27", isFavourite: false, isHidden: false, syncEnabled: true)
        let section = CourseSection(id: 1, name: "S", position: 0, summary: nil)
        folder = CourseModule(id: 1, name: "Exercises", modname: "folder", instance: 1, url: nil, descriptionHTML: nil, position: 0)
        context.insert(course); context.insert(section); context.insert(folder)
        section.course = course
        folder.section = section
    }

    private func file(_ name: String, key: String, downloaded: Bool, removed: Bool) throws -> FileItem {
        let f = FileItem(key: key, filename: name, filepath: "/", filesize: 3, timemodified: .now, mimetype: nil,
                         remoteURL: key, firstSeenAt: .now)
        context.insert(f)
        f.course = course
        f.module = folder
        if downloaded {
            let temp = root.appending(path: UUID().uuidString)
            try Data([1, 2, 3]).write(to: temp)
            try local.store(temp, for: f)
            f.state = .downloaded
        }
        if removed { f.removedAt = removal }
        return f
    }

    private func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: relative).path(percentEncoded: false))
    }

    @Test func aDownloadedRemovedFileIsRenamedAndFreesItsKey() throws {
        let f = try file("lesson 2.pdf", key: "k/lesson2", downloaded: true, removed: true)
        let live = try file("lesson 3.pdf", key: "k/lesson3", downloaded: true, removed: false)
        try context.save()

        let settled = try RemovedContent.settle(in: context, local: local, keep: true, label: "rimosso", timeZone: .gmt)

        #expect(settled == 1)
        #expect(f.localRelativePath == "FLC/2026-27/Exercises/[rimosso 2026-11-10] lesson 2.pdf")
        #expect(exists("FLC/2026-27/Exercises/[rimosso 2026-11-10] lesson 2.pdf"))
        #expect(!exists("FLC/2026-27/Exercises/lesson 2.pdf"))
        #expect(f.key != "k/lesson2" && f.key.hasPrefix("k/lesson2"))
        #expect(f.filename == "lesson 2.pdf")
        #expect(f.isKeptRemoved)
        #expect(live.localRelativePath == "FLC/2026-27/Exercises/lesson 3.pdf" && live.key == "k/lesson3")
        // The layout migration that runs at every sync must leave the renamed file alone.
        #expect(local.relativePath(for: f) == f.localRelativePath)
        #expect(local.migrateLayout(courses: [course]) == 0)

        // Nothing left to settle; a new file with the old name does not touch the keepsake.
        #expect(try RemovedContent.settle(in: context, local: local, keep: true, label: "rimosso", timeZone: .gmt) == 0)
        let fresh = try file("lesson 2.pdf", key: "k/lesson2", downloaded: true, removed: false)
        try context.save()
        #expect(fresh.localRelativePath == "FLC/2026-27/Exercises/lesson 2.pdf")
        #expect(exists("FLC/2026-27/Exercises/[rimosso 2026-11-10] lesson 2.pdf"))
    }

    @Test func twoRemovalsOfTheSameNameOnTheSameDayDoNotCollide() throws {
        _ = try file("a.pdf", key: "k/a", downloaded: true, removed: true)
        try context.save()
        _ = try RemovedContent.settle(in: context, local: local, keep: true, label: "rimosso", timeZone: .gmt)
        let second = try file("a.pdf", key: "k/a", downloaded: true, removed: true)
        try context.save()
        _ = try RemovedContent.settle(in: context, local: local, keep: true, label: "rimosso", timeZone: .gmt)

        #expect(exists("FLC/2026-27/Exercises/[rimosso 2026-11-10] a.pdf"))
        #expect(second.localRelativePath == "FLC/2026-27/Exercises/[rimosso 2026-11-10] a 2.pdf")
        #expect(exists("FLC/2026-27/Exercises/[rimosso 2026-11-10] a 2.pdf"))
    }

    @Test func aRemovedFileMissingOnDiskIsNotKept() throws {
        let f = try file("a.pdf", key: "k/a", downloaded: true, removed: true)
        try FileManager.default.removeItem(at: root.appending(path: f.localRelativePath!))
        try context.save()
        #expect(try RemovedContent.settle(in: context, local: local, keep: true, label: "rimosso", timeZone: .gmt) == 0)
        #expect(!f.isKeptRemoved)
    }

    @Test func purgeDropsWhatIsNotKeptAndTheEmptyModules() throws {
        let kept = try file("kept.pdf", key: "k/kept", downloaded: true, removed: true)
        _ = try file("gone.pdf", key: "k/gone", downloaded: false, removed: true)
        _ = try file("live.pdf", key: "k/live", downloaded: false, removed: false)
        let emptyModule = CourseModule(id: 2, name: "Old", modname: "resource", instance: 2, url: nil, descriptionHTML: nil, position: 1)
        context.insert(emptyModule)
        emptyModule.section = folder.section
        emptyModule.removedAt = removal
        try context.save()
        _ = try RemovedContent.settle(in: context, local: local, keep: true, label: "rimosso", timeZone: .gmt)

        try RemovedContent.purge(in: context, keep: true)

        let names = try context.fetch(FetchDescriptor<FileItem>()).map(\.filename).sorted()
        #expect(names == ["kept.pdf", "live.pdf"])
        #expect(try context.fetch(FetchDescriptor<CourseModule>()).map(\.id) == [1])
        #expect(kept.isKeptRemoved)
    }

    @Test func withKeepingOffRemovedFilesLeaveTheAppButStayOnDisk() throws {
        let f = try file("a.pdf", key: "k/a", downloaded: true, removed: true)
        let path = try #require(f.localRelativePath)
        try context.save()

        #expect(try RemovedContent.settle(in: context, local: local, keep: false, label: "rimosso", timeZone: .gmt) == 0)
        #expect(exists(path))
        try RemovedContent.purge(in: context, keep: false)

        #expect(try context.fetchCount(FetchDescriptor<FileItem>()) == 0)
        #expect(exists(path))
    }
}
