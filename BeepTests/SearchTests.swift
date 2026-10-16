import Foundation
import SwiftData
import Testing
@testable import Beep

/// Every search in the app: courses (home, Search, auto-download settings), files across
/// courses (Search), files inside one course.
@MainActor
struct SearchTests {
    let context: ModelContext

    init() throws {
        context = ModelContext(try StoreContainer.make(inMemory: true))
        context.autosaveEnabled = false
    }

    private func course(_ id: Int, _ title: String, code: String? = nil, profs: String? = nil, year: String = "2026-27",
                        hidden: Bool = false, archived: Bool = false) -> Course {
        let c = Course(id: id, fullname: "", displayName: "", title: title, code: code, professors: profs,
                       categoryID: 0, categoryName: year, isFavourite: false, isHidden: hidden, syncEnabled: false)
        c.isArchived = archived
        context.insert(c)
        return c
    }

    private func file(_ key: String, _ name: String, path: String = "/", in course: Course, module: CourseModule? = nil,
                      days: Double = 0, seen: Date = .distantPast) -> FileItem {
        let f = FileItem(key: key, filename: name, filepath: path, filesize: 1,
                         timemodified: Date(timeIntervalSince1970: 1_800_000_000 + days * 86_400),
                         mimetype: nil, remoteURL: "https://x/\(key)", firstSeenAt: seen)
        context.insert(f)
        f.course = course
        f.module = module
        return f
    }

    private func module(_ id: Int, _ name: String, kind: String = "folder", position: Int = 0, section: CourseSection) -> CourseModule {
        let m = CourseModule(id: id, name: name, modname: kind, instance: nil, url: nil, descriptionHTML: nil, position: position)
        context.insert(m)
        m.section = section
        return m
    }

    private func section(_ id: Int, _ name: String, position: Int, in course: Course) -> CourseSection {
        let s = CourseSection(id: id, name: name, position: position, summary: nil)
        context.insert(s)
        s.course = course
        return s
    }

    // MARK: Courses

    @Test func coursesMatchTitleCodeAndProfessorIgnoringCaseAndAccents() {
        let db2 = course(1, "Data Bases 2", code: "089183", profs: "Comai Sara")
        let fis = course(2, "Fisica Tecnica", code: "052", profs: "Nicolò Bianchi")
        #expect(db2.matches("data bases"))
        #expect(db2.matches("089183"))
        #expect(db2.matches("comai"))
        #expect(db2.matches("SARA"))
        #expect(fis.matches("nicolo"))
        #expect(!db2.matches("fraternali"))
        #expect(db2.matches(""))
        #expect(db2.matches("   "))
    }

    @Test func autoDownloadListFiltersByYearQueryAndHidesHiddenOrArchived() {
        let current = course(1, "Data Bases 2", profs: "Comai Sara", year: "\(AcademicYear.currentStartYear())-\(String(AcademicYear.currentStartYear() + 1).suffix(2))")
        let old = course(2, "Data Bases 2", profs: "Comai Sara", year: "2019-20")
        _ = course(3, "Hidden", profs: "Comai Sara", hidden: true)
        _ = course(4, "Archived", profs: "Comai Sara", archived: true)
        let all = (try? context.fetch(FetchDescriptor<Course>(sortBy: [SortDescriptor(\.id)]))) ?? []
        #expect(SyncCoursesView.visible(all, query: "comai", years: .all).map(\.id) == [current.id, old.id])
        #expect(SyncCoursesView.visible(all, query: "comai", years: .current).map(\.id) == [current.id])
        #expect(SyncCoursesView.visible(all, query: "comai", years: .past).map(\.id) == [old.id])
        #expect(SyncCoursesView.visible(all, query: "nobody", years: .all).isEmpty)
    }

    // MARK: Files across courses

    @Test func fileSearchMatchesNameFolderAndModuleNewestFirst() throws {
        let c = course(1, "Data Bases 2")
        let s = section(10, "Lezioni", position: 0, in: c)
        let triggers = module(100, "Triggers", section: s)
        let a = file("a", "02-Transactions.pdf", in: c, days: 1)
        let b = file("b", "notes.txt", path: "/Transactions/", in: c, days: 3)
        let m = file("m", "lab.zip", in: c, module: triggers, days: 2)
        _ = file("x", "unrelated.pdf", in: c)
        try context.save()

        #expect(GlobalSearchView.files(matching: "transactions", scope: .all, in: context).map(\.key) == [b.key, a.key])
        #expect(GlobalSearchView.files(matching: "TRIGGERS", scope: .all, in: context).map(\.key) == [m.key])
        #expect(GlobalSearchView.files(matching: "transactions", scope: .pdf, in: context).map(\.key) == [a.key])
        #expect(GlobalSearchView.files(matching: "nothing-like-this", scope: .all, in: context).isEmpty)
    }

    @Test func fileSearchStopsAtTwoHundredResults() throws {
        let c = course(1, "Big")
        for i in 0..<250 { _ = file("k\(i)", "slide \(i).pdf", in: c, days: Double(i)) }
        try context.save()
        let found = GlobalSearchView.files(matching: "slide", scope: .all, in: context)
        #expect(found.count == 200)
        #expect(found.first?.key == "k249")
    }

    // MARK: Inside one course

    @Test func courseFilterMatchesQueryScopeAndNewFiles() throws {
        let c = course(1, "Formal Languages")
        let s0 = section(10, "Intro", position: 0, in: c), s1 = section(11, "Exercises", position: 1, in: c)
        let intro = module(100, "Slides", position: 0, section: s0)
        let ex = module(101, "Esercizi", position: 0, section: s1)
        let lastSeen = Date(timeIntervalSince1970: 1_700_000_000)
        let a = file("a", "grammars.pdf", in: c, module: intro, seen: lastSeen.addingTimeInterval(-10))
        let b = file("b", "esercizio-1.pdf", in: c, module: ex, days: 5, seen: lastSeen.addingTimeInterval(10))
        let z = file("z", "esercizio-2.zip", in: c, module: ex, days: 1, seen: lastSeen.addingTimeInterval(10))
        try context.save()

        func run(_ q: String, _ scope: FileTypeScope = .all, sort: FileSort = .position, onlyNew: Bool = false) -> [String] {
            FilteredFilesSection.files(of: c, query: q, scope: scope, sort: sort, onlyNew: onlyNew, lastSeen: lastSeen).map(\.key)
        }
        #expect(run("ESERCIZIO", sort: .name) == [b.key, z.key])
        #expect(run("esercizi", .pdf) == [b.key])
        #expect(run("slides") == [a.key])                       // module name
        #expect(run("", sort: .newest, onlyNew: true) == [b.key, z.key])
        #expect(run("") == [a.key, b.key, z.key])                // course order: section, module, name
    }
}
