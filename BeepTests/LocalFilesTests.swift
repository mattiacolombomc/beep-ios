import Foundation
import Testing
@testable import Beep

@MainActor
struct LocalFilesTests {
    @Test func sanitizesComponents() {
        #expect(LocalFiles.sanitize("Software Engineering 2") == "Software Engineering 2")
        #expect(LocalFiles.sanitize("A/B: C\\D") == "A-B- C-D")
        #expect(LocalFiles.sanitize("  ..hidden..  ") == "hidden")
        #expect(LocalFiles.sanitize("") == "_")
    }

    @Test func storesAndFindsFilesWithSpacesInPath() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "beep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalFiles(root: root)

        let file = FileItem(key: "k", filename: "01 intro.pdf", filepath: "/Week 1/", filesize: 3, timemodified: .now,
                            mimetype: nil, remoteURL: "https://x/1", firstSeenAt: .now)
        let module = CourseModule(id: 1, name: "Lessons", modname: "folder", instance: 1, url: nil, descriptionHTML: nil, position: 0)
        let course = Course(id: 1, fullname: "", displayName: "", title: "Distributed Systems", code: nil, professors: nil,
                            categoryID: 0, categoryName: "2026-27", isFavourite: false, isHidden: false, syncEnabled: true)
        file.module = module
        file.course = course

        let temp = root.appending(path: "tmp.bin")
        try Data([1, 2, 3]).write(to: temp)
        try local.store(temp, for: file)

        #expect(file.localRelativePath == "Distributed Systems/2026-27/Lessons/Week 1/01 intro.pdf")
        let url = try #require(local.url(for: file))
        #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        local.remove(file)
        #expect(local.url(for: file) == nil)
    }

    @Test func renamesCourseFolderAndRewritesPaths() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "beep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalFiles(root: root)
        let course = Course(id: 7, fullname: "", displayName: "", title: "Data Bases 2", code: nil, professors: nil,
                            categoryID: 0, categoryName: "2026-27", isFavourite: false, isHidden: false, syncEnabled: true)
        course.folderName = "Data Bases 2"
        let file = FileItem(key: "k2", filename: "a.pdf", filepath: "/", filesize: 1, timemodified: .now, mimetype: nil, remoteURL: "https://x/a", firstSeenAt: .now)
        file.course = course
        let temp = root.appending(path: "tmp.bin")
        try Data([1]).write(to: temp)
        try local.store(temp, for: file)
        #expect(file.localRelativePath == "Data Bases 2/2026-27/a.pdf")

        try local.renameCourseFolder(course, to: "DB2")
        #expect(course.folderName == "DB2")
        #expect(file.localRelativePath == "DB2/2026-27/a.pdf")
        #expect(local.url(for: file) != nil)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Data Bases 2").path(percentEncoded: false)))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "beep-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func course(_ id: Int, title: String, year: String, professors: String? = nil, folder: String? = nil) -> Course {
        let c = Course(id: id, fullname: "", displayName: "", title: title, code: nil, professors: professors,
                       categoryID: 0, categoryName: year, isFavourite: false, isHidden: false, syncEnabled: true)
        c.folderName = folder ?? title
        return c
    }

    @Test func renamingOneEditionLeavesTheOtherAlone() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalFiles(root: root)
        let old = course(1, title: "Data Bases 2", year: "2025-26"), new = course(2, title: "Data Bases 2", year: "2026-27")
        let a = FileItem(key: "a", filename: "a.pdf", filepath: "/", filesize: 1, timemodified: .now, mimetype: nil, remoteURL: "https://x/a", firstSeenAt: .now)
        let b = FileItem(key: "b", filename: "b.pdf", filepath: "/", filesize: 1, timemodified: .now, mimetype: nil, remoteURL: "https://x/b", firstSeenAt: .now)
        a.course = old; b.course = new
        for (f, name) in [(a, "ta"), (b, "tb")] {
            let temp = root.appending(path: name)
            try Data([1]).write(to: temp)
            try local.store(temp, for: f)
        }
        #expect(a.localRelativePath == "Data Bases 2/2025-26/a.pdf")
        #expect(b.localRelativePath == "Data Bases 2/2026-27/b.pdf")
        #expect(local.directory(of: old)?.lastPathComponent == "2025-26")

        try local.renameCourseFolder(old, to: "DB2 old")
        #expect(a.localRelativePath == "DB2 old/2025-26/a.pdf")
        #expect(b.localRelativePath == "Data Bases 2/2026-27/b.pdf")
        #expect(local.url(for: a) != nil)
        #expect(local.url(for: b) != nil)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Data Bases 2/2025-26").path(percentEncoded: false)))
        #expect(local.directory(of: new) != nil)
    }

    @Test func migratesFlatLayoutIntoYearFolders() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let local = LocalFiles(root: root)
        // Old layout: a suffixed folder for the old edition, a plain one for the new, a user rename for a third course.
        let comai = course(1, title: "Data Bases 2", year: "2025-26", professors: "Comai Sara", folder: "Data Bases 2 (Comai Sara)")
        let fraternali = course(2, title: "Data Bases 2", year: "2026-27", professors: "Fraternali Piero")
        let renamed = course(3, title: "Distributed Systems", year: "2025-26", professors: "Cugola Gianpaolo", folder: "DS")
        // Two sections in the same year: they get the professor in the edition folder.
        let comai27 = course(4, title: "Data Bases 2", year: "2026-27", professors: "Comai Sara")
        func seed(_ course: Course, key: String, oldRel: String) throws -> FileItem {
            let f = FileItem(key: key, filename: URL(filePath: oldRel).lastPathComponent, filepath: "/", filesize: 1, timemodified: .now, mimetype: nil, remoteURL: "https://x/\(key)", firstSeenAt: .now)
            f.course = course
            f.state = .downloaded
            f.localRelativePath = oldRel
            let url = root.appending(path: oldRel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([1]).write(to: url)
            return f
        }
        let a = try seed(comai, key: "a", oldRel: "Data Bases 2 (Comai Sara)/a.pdf")
        let b = try seed(fraternali, key: "b", oldRel: "Data Bases 2/b.pdf")
        let c = try seed(renamed, key: "c", oldRel: "DS/c.pdf")
        let missing = try seed(fraternali, key: "m", oldRel: "Data Bases 2/missing.pdf")
        try FileManager.default.removeItem(at: root.appending(path: "Data Bases 2/missing.pdf"))
        let d = try seed(comai27, key: "d", oldRel: "Data Bases 2 (Comai Sara)/d.pdf")

        local.migrateLayout(courses: [comai, fraternali, renamed, comai27])

        #expect(comai.folderName == "Data Bases 2")
        #expect(a.localRelativePath == "Data Bases 2/2025-26/a.pdf")
        #expect(b.localRelativePath == "Data Bases 2/2026-27 (Fraternali Piero)/b.pdf")
        #expect(d.localRelativePath == "Data Bases 2/2026-27 (Comai Sara)/d.pdf")
        #expect(renamed.folderName == "DS")
        #expect(c.localRelativePath == "DS/2025-26/c.pdf")
        #expect(missing.localRelativePath == "Data Bases 2/missing.pdf")
        for f in [a, b, c, d] { #expect(local.url(for: f) != nil) }
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Data Bases 2 (Comai Sara)").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: root.path(percentEncoded: false)))
        // Running again changes nothing.
        local.migrateLayout(courses: [comai, fraternali, renamed, comai27])
        #expect(a.localRelativePath == "Data Bases 2/2025-26/a.pdf")
        #expect(b.localRelativePath == "Data Bases 2/2026-27 (Fraternali Piero)/b.pdf")
    }
}
