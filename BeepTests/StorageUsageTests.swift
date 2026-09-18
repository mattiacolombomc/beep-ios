import Foundation
import SwiftData
import Testing
@testable import Beep

@MainActor
struct StorageUsageTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try StoreContainer.make(inMemory: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private func course(_ id: Int, _ title: String) -> Course {
        let c = Course(id: id, fullname: title, displayName: title, title: title, code: nil, professors: nil,
                       categoryID: 1, categoryName: "2026-27", isFavourite: false, isHidden: false, syncEnabled: false)
        context.insert(c)
        return c
    }

    private func file(_ key: String, size: Int, downloaded: Bool, in course: Course) {
        let f = FileItem(key: key, filename: key + ".pdf", filepath: "/", filesize: size, timemodified: .now,
                         mimetype: nil, remoteURL: "https://example.com/" + key, firstSeenAt: .now)
        context.insert(f)
        f.course = course
        if downloaded {
            f.state = .downloaded
            f.localRelativePath = course.title + "/" + f.filename
        }
    }

    @Test func countsOnlyDownloadedFilesLargestFirst() throws {
        let small = course(1, "Data Bases 2")
        let big = course(2, "Formal Languages")
        let none = course(3, "Distributed Systems")
        file("a", size: 100, downloaded: true, in: small)
        file("b", size: 5_000, downloaded: false, in: small)
        file("c", size: 700, downloaded: true, in: big)
        file("d", size: 300, downloaded: true, in: big)
        file("e", size: 9_999, downloaded: false, in: none)
        try context.save()

        let usage = StorageUsage.byCourse([small, big, none])

        #expect(usage.map(\.course.id) == [2, 1])
        #expect(usage[0].bytes == 1_000)
        #expect(usage[0].files == 2)
        #expect(usage[1].bytes == 100)
        #expect(usage[1].files == 1)
    }
}
