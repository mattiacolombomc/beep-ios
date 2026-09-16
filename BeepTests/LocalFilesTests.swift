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

        #expect(file.localRelativePath == "Distributed Systems/Lessons/Week 1/01 intro.pdf")
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
        #expect(file.localRelativePath == "Data Bases 2/a.pdf")

        try local.renameCourseFolder(course, to: "DB2")
        #expect(course.folderName == "DB2")
        #expect(file.localRelativePath == "DB2/a.pdf")
        #expect(local.url(for: file) != nil)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Data Bases 2").path(percentEncoded: false)))
    }
}
