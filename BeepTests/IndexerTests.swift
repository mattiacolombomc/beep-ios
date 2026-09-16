import Foundation
import SwiftData
import Testing
@testable import Beep

private func fixture(_ name: String) throws -> Data {
    final class Anchor {}
    let url = try #require(Bundle(for: Anchor.self).url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

@MainActor
struct IndexerTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try StoreContainer.make(inMemory: true)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    private func seedCourses() throws -> Course {
        let courses = try MoodleClient.decode([CourseDTO].self, from: try fixture("users_courses"))
        let cats = try MoodleClient.decode([CategoryDTO].self, from: try fixture("categories"))
        let indexer = Indexer(context: context, language: "en")
        let diff = try indexer.upsertCourses(courses, categories: cats) { _, category in AcademicYear.isAcademicYear(category) }
        #expect(diff.inserted.count == 2)
        return try #require(try context.fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.id == 41213 })).first)
    }

    @Test func coursesGetParsedTitlesAndCategoryNames() throws {
        let course = try seedCourses()
        #expect(course.title == "Software Engineering 2")
        #expect(course.code == "054443")
        #expect(course.categoryName == "2026-27")
        #expect(course.syncEnabled)
        let ccs = try #require(try context.fetch(FetchDescriptor<Course>(predicate: #Predicate { $0.id == 40001 })).first)
        #expect(ccs.title == "Computer Engineering")
        #expect(ccs.isHidden)
        #expect(!ccs.syncEnabled)
    }

    @Test func duplicateTitlesGetDistinctFolders() throws {
        let cats = [CategoryDTO(id: 1, name: "2026-27", parent: 0)]
        let a = CourseDTO(id: 1, fullname: "088983 - FOUNDATIONS OF OPERATIONS RESEARCH (MALUCELLI FEDERICO)", displayname: "088983 - FOUNDATIONS OF OPERATIONS RESEARCH (MALUCELLI FEDERICO)", shortname: nil, category: 1, hidden: false, isfavourite: false, lastaccess: nil, timemodified: nil)
        let b = CourseDTO(id: 2, fullname: "088983 - FOUNDATIONS OF OPERATIONS RESEARCH (AMALDI EDOARDO)", displayname: "088983 - FOUNDATIONS OF OPERATIONS RESEARCH (AMALDI EDOARDO)", shortname: nil, category: 1, hidden: false, isfavourite: false, lastaccess: nil, timemodified: nil)
        let c = CourseDTO(id: 3, fullname: "052537 - DATA BASES 2 (CAPPIELLO CINZIA)", displayname: "052537 - DATA BASES 2 (CAPPIELLO CINZIA)", shortname: nil, category: 1, hidden: false, isfavourite: false, lastaccess: nil, timemodified: nil)
        try Indexer(context: context).upsertCourses([a, b, c], categories: cats) { _, _ in true }
        let all = try context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.id)]))
        #expect(all[0].folderName == "Foundations of Operations Research (Malucelli Federico)")
        #expect(all[1].folderName == "Foundations of Operations Research (Amaldi Edoardo)")
        #expect(all[2].folderName == "Data Bases 2")
    }

    @Test func reindexKeepsLocalFlagsAndRemovesUnenrolled() throws {
        let course = try seedCourses()
        course.syncEnabled = false
        course.lastSeenAt = Date(timeIntervalSince1970: 1)
        var courses = try MoodleClient.decode([CourseDTO].self, from: try fixture("users_courses"))
        courses.removeLast()
        let cats = try MoodleClient.decode([CategoryDTO].self, from: try fixture("categories"))
        let diff = try Indexer(context: context).upsertCourses(courses, categories: cats) { _, _ in true }
        #expect(diff.removed == [40001])
        #expect(try context.fetch(FetchDescriptor<Course>()).count == 1)
        #expect(!course.syncEnabled)
    }

    @Test func contentsBuildSectionsModulesFilesAndDiff() throws {
        let course = try seedCourses()
        let sections = try MoodleClient.decode([SectionDTO].self, from: try fixture("course_contents"))
        let t0 = Date(timeIntervalSince1970: 1_000)
        let indexer = Indexer(context: context, language: "it", now: { t0 })
        let diff = try indexer.upsertContents(sections, for: course, token: "TOK")

        #expect(course.sections.count == 2)
        #expect(course.sections.sorted { $0.position < $1.position }.map(\.name) == ["Introduzione", "Materiali"])
        let materials = course.sections.first { $0.name == "Materiali" }!
        #expect(materials.modules.count == 4)
        // page's index.html is a file too; url module contents are skipped
        #expect(course.files.count == 4)
        #expect(diff.newFiles.count == 4)
        #expect(diff.updatedFiles.isEmpty)
        let sol = course.files.first { $0.filename == "sol01.pdf" }!
        #expect(sol.filepath == "/Solutions/")
        #expect(sol.remoteURL.hasSuffix("?forcedownload=1&token=TOK"))
        #expect(sol.key.hasSuffix("?forcedownload=1"))
        #expect(sol.firstSeenAt == t0)
        #expect(course.lastSeenAt == t0)
        #expect(course.files.allSatisfy { !$0.isNew(relativeTo: course.lastSeenAt) })

        // Second pass: one file updated, one removed, one added.
        var s2 = sections
        var mats = s2[1]
        var folder = mats.modules[1]
        var contents = folder.contents!
        contents[0] = ContentDTO(type: "file", filename: "ex01.pdf", filepath: "/", filesize: 150,
                                 fileurl: contents[0].fileurl, timemodified: 1_800_000_000, timecreated: nil, mimetype: "application/pdf", author: nil)
        contents.remove(at: 1)
        contents.append(ContentDTO(type: "file", filename: "ex02.pdf", filepath: "/", filesize: 1,
                                   fileurl: "https://webeep.polimi.it/webservice/pluginfile.php/4/mod_folder/content/0/ex02.pdf?forcedownload=1",
                                   timemodified: 1_800_000_001, timecreated: nil, mimetype: "application/pdf", author: nil))
        folder = ModuleDTO(id: folder.id, name: folder.name, modname: folder.modname, instance: folder.instance, url: folder.url,
                           description: folder.description, visible: folder.visible, uservisible: folder.uservisible, contents: contents)
        mats = SectionDTO(id: mats.id, name: mats.name, section: mats.section, summary: mats.summary, visible: mats.visible,
                          uservisible: mats.uservisible, modules: [mats.modules[0], folder, mats.modules[2], mats.modules[3]])
        s2[1] = mats
        let t1 = Date(timeIntervalSince1970: 2_000)
        let diff2 = try Indexer(context: context, language: "it", now: { t1 }).upsertContents(s2, for: course, token: "TOK")
        #expect(diff2.newFiles.count == 1)
        #expect(diff2.updatedFiles.count == 1)
        #expect(diff2.removedFiles.count == 1)
        #expect(course.files.count == 4)
        let ex02 = course.files.first { $0.filename == "ex02.pdf" }!
        #expect(ex02.isNew(relativeTo: course.lastSeenAt))
        #expect(course.files.first { $0.filename == "ex01.pdf" }!.filesize == 150)
    }
}
