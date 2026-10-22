import CoreSpotlight
import Foundation
import SwiftData
import Testing
@testable import Beep

/// The Spotlight index is built from a snapshot of plain values taken on the IndexActor, never from
/// live models: TestFlight 0.2.0 (16) crashed in the background when the detached reindex, suspended
/// mid-way, resumed and faulted a FileItem that the next sync had deleted (`_InvalidFutureBackingData`).
struct SpotlightIndexerTests {
    let container: ModelContainer

    init() throws {
        container = try StoreContainer.make(inMemory: true)
    }

    @MainActor
    private func seed() throws -> (Course, [FileItem]) {
        let context = container.mainContext
        let db2 = Course(id: 1, fullname: "", displayName: "", title: "Data Bases 2", code: "089183", professors: "Comai Sara",
                         categoryID: 0, categoryName: "2026-27", isFavourite: false, isHidden: false, syncEnabled: false)
        let old = Course(id: 2, fullname: "", displayName: "", title: "Archived", code: nil, professors: nil,
                         categoryID: 0, categoryName: "2019-20", isFavourite: false, isHidden: false, syncEnabled: false)
        old.isArchived = true
        context.insert(db2)
        context.insert(old)
        let section = CourseSection(id: 10, name: "Lectures", position: 0, summary: nil)
        context.insert(section)
        section.course = db2
        let module = CourseModule(id: 100, name: "Triggers", modname: "folder", instance: nil, url: nil, descriptionHTML: nil, position: 0)
        context.insert(module)
        module.section = section
        let a = FileItem(key: "a", filename: "02-Transactions.PDF", filepath: "/", filesize: 1,
                         timemodified: Date(timeIntervalSince1970: 1_800_000_000), mimetype: nil, remoteURL: "https://x/a", firstSeenAt: .distantPast)
        let b = FileItem(key: "b", filename: "notes", filepath: "/", filesize: 1,
                         timemodified: Date(timeIntervalSince1970: 1_800_000_100), mimetype: nil, remoteURL: "https://x/b", firstSeenAt: .distantPast)
        let z = FileItem(key: "z", filename: "old.zip", filepath: "/", filesize: 1,
                         timemodified: Date(timeIntervalSince1970: 1_700_000_000), mimetype: nil, remoteURL: "https://x/z", firstSeenAt: .distantPast)
        for f in [a, b, z] { context.insert(f) }
        a.course = db2; a.module = module
        b.course = db2
        z.course = old
        try context.save()
        return (db2, [a, b, z])
    }

    @Test func snapshotSkipsArchivedCoursesAndCarriesModuleAndExtension() async throws {
        _ = try await seed()
        let entries = try await IndexActor(modelContainer: container).spotlightEntries()
        #expect(entries.courses.map(\.id) == [1])
        #expect(entries.courses.first?.title == "Data Bases 2")
        #expect(entries.courses.first?.description == "089183 · Comai Sara · 2026-27")
        #expect(entries.files.map(\.key).sorted() == ["a", "b"])
        let a = try #require(entries.files.first { $0.key == "a" })
        #expect(a.filename == "02-Transactions.PDF")
        #expect(a.fileExtension == "pdf")
        #expect(a.description == "Data Bases 2 › Triggers")
        #expect(a.courseTitle == "Data Bases 2")
        #expect(a.modified == Date(timeIntervalSince1970: 1_800_000_000))
        let b = try #require(entries.files.first { $0.key == "b" })
        #expect(b.description == "Data Bases 2")
        #expect(b.fileExtension == "")
    }

    @Test func snapshotOutlivesADeleteInTheStore() async throws {
        let (course, files) = try await seed()
        let entries = try await IndexActor(modelContainer: container).spotlightEntries()
        // The next sync removes a file and a whole course while the index is still being built.
        try await MainActor.run {
            container.mainContext.delete(files[0])
            container.mainContext.delete(course)
            try container.mainContext.save()
        }
        let items = SpotlightIndexer.items(from: entries)
        #expect(items.map(\.uniqueIdentifier).sorted() == ["course:1", "file:a", "file:b"])
    }

    @Test func itemsCarryDomainsIdentifiersAndTypes() async throws {
        _ = try await seed()
        let entries = try await IndexActor(modelContainer: container).spotlightEntries()
        let items = SpotlightIndexer.items(from: entries)
        let course = try #require(items.first { $0.uniqueIdentifier == "course:1" })
        #expect(course.domainIdentifier == SpotlightIndexer.courseDomain)
        #expect(course.attributeSet.title == "Data Bases 2")
        let a = try #require(items.first { $0.uniqueIdentifier == "file:a" })
        #expect(a.domainIdentifier == SpotlightIndexer.fileDomain)
        #expect(a.attributeSet.title == "02-Transactions.PDF")
        #expect(a.attributeSet.contentType == "com.adobe.pdf")
        #expect(a.attributeSet.contentDescription == "Data Bases 2 › Triggers")
        #expect(a.attributeSet.contentModificationDate == Date(timeIntervalSince1970: 1_800_000_000))
        let b = try #require(items.first { $0.uniqueIdentifier == "file:b" })
        #expect(b.attributeSet.contentType == "public.data")
    }

    @Test func spotlightActivityOpensCourseOrFile() {
        func activity(_ id: String) -> NSUserActivity {
            let a = NSUserActivity(activityType: CSSearchableItemActionType)
            a.userInfo = [CSSearchableItemActivityIdentifier: id]
            return a
        }
        #expect(SpotlightIndexer.destination(for: activity("course:42")) == .course(42))
        #expect(SpotlightIndexer.destination(for: activity("file:k1")) == .file("k1"))
        #expect(SpotlightIndexer.destination(for: activity("other")) == nil)
    }
}
