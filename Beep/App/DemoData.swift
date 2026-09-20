import Foundation
import SwiftData

/// Sample store for previews and for `-demo` launches (UI work without WeBeep credentials).
enum DemoData {
    /// Demo is on for `-demo` launches and after a reviewer signs in with `reviewPassword`.
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-demo") || UserDefaults.standard.bool(forKey: flagKey)
    }
    static let flagKey = "demo.enabled"
    /// "Password" for App Review's demonstration mode; entered in the manual-token sheet.
    static let reviewPassword = "BeepReview2026"

    /// Turns the current session into the demo (sample data, no WeBeep calls) until sign-out.
    @MainActor
    static func enter(session: AppSession, context: ModelContext) throws {
        UserDefaults.standard.set(true, forKey: flagKey)
        try context.delete(model: Course.self)
        try context.delete(model: WebeepNotification.self)
        try seed(into: context)
        session.enterDemo()
    }

    @MainActor
    static func seed(into context: ModelContext) throws {
        let cats = [CategoryDTO(id: 1210, name: "2026-27", parent: 0), CategoryDTO(id: 1100, name: "2025-26", parent: 0),
                    CategoryDTO(id: 1000, name: "2024-25", parent: 0), CategoryDTO(id: 77, name: "CCS", parent: 0)]
        func c(_ id: Int, _ name: String, _ cat: Int, fav: Bool = false, hidden: Bool = false, access: Int? = nil) -> CourseDTO {
            CourseDTO(id: id, fullname: name, displayname: name, shortname: nil, category: cat, hidden: hidden, isfavourite: fav, lastaccess: access, timemodified: nil)
        }
        let courses = [
            c(41213, "054443 - SOFTWARE ENGINEERING 2 (CAMILLI MATTEO, DI NITTO ELISABETTA, ROSSI MATTEO GIOVANNI)", 1210, fav: true),
            c(41214, "ARTIFICIAL NEURAL NETWORKS AND DEEP LEARNING (054307 +056869 BORACCHI-MATTEUCCI) [2026-27]", 1210),
            c(41215, "056896 - OFFENSIVE AND DEFENSIVE CYBERSECURITY (BINOSI LORENZO)", 1210),
            c(41216, "089182 - FORMAL LANGUAGES AND COMPILERS (BREVEGLIERI LUCA ODDONE)", 1210, fav: true),
            c(41217, "088983 - FOUNDATIONS OF OPERATIONS RESEARCH (MALUCELLI FEDERICO)", 1210),
            c(41218, "099322 - SEGNALI PER LE COMUNICAZIONI (PRATI CLAUDIO MARIA)", 1210),
            c(41219, "052537 - DATA BASES 2 (CAPPIELLO CINZIA)", 1210),
            c(41220, "095946 - DISTRIBUTED SYSTEMS (CUGOLA GIANPAOLO)", 1210),
            c(40001, "{mlang it}Ingegneria Informatica{mlang}{mlang en}Computer Engineering{mlang}", 77),
            c(30001, "051144 - ANALISI MATEMATICA II (BARUTELLO VIVINA)", 1100),
            c(30002, "085877 - FONDAMENTI DI ELETTRONICA (SAMPIETRO MARCO)", 1100),
            c(30003, "086067 - LOGICA E ALGEBRA (ZAMPIERI MARIA)", 1100),
            c(20001, "083424 - FISICA SPERIMENTALE (BOTTANI CARLO)", 1000),
            c(20002, "081375 - ANALISI MATEMATICA I (VERZINI GIANMARIA)", 1000, hidden: true),
        ]
        let indexer = Indexer(context: context, language: "it", now: { Date.now.addingTimeInterval(-3600) })
        try indexer.upsertCourses(courses, categories: cats) { _, cat in AcademicYear.isCurrent(cat) }

        let all = try context.fetch(FetchDescriptor<Course>())
        for course in all where course.categoryName == "2026-27" {
            try indexer.upsertContents(sections(for: course.id), for: course, token: "demo")
        }
        // Make a few files "new" on the two favourite courses.
        for course in all where course.isFavourite {
            course.lastSeenAt = Date.now.addingTimeInterval(-86_400 * 3)
            for (i, f) in course.files.enumerated() where i % 3 == 0 { f.firstSeenAt = Date.now.addingTimeInterval(-3600) }
            course.recountNewFiles()
        }
        // Sample announcements for the notifications screen.
        context.insert(WebeepNotification(
            id: 900_001, subject: "Software Engineering 2: Lab groups and first deadline",
            htmlBody: "<p>Dear students,</p><p>lab groups of <b>three people</b> must be registered by Friday. The first deliverable is due on October 12.</p><p>See the course page for the template.</p>",
            contextURL: "https://webeep.polimi.it/course/view.php?id=41213", contextName: "Lab groups and first deadline",
            timecreated: Date.now.addingTimeInterval(-3600 * 5), read: false))
        context.insert(WebeepNotification(
            id: 900_002, subject: "Formal Languages and Compilers: calendar change",
            htmlBody: "<p>The lecture of Thursday moves to room <b>3.1.3</b>, same time.</p>",
            contextURL: nil, contextName: "calendar change",
            timecreated: Date.now.addingTimeInterval(-86_400 * 2), read: true))
        try context.save()
    }

    /// Sample WeBeep catalogue for demo mode (App Review and screenshots): public-looking courses,
    /// one of them already in the demo list so the "enrolled" state is visible too.
    static func catalog(matching query: String) -> [CatalogCourseDTO] {
        let all: [(Int, String, String)] = [
            (41216, "089182 - FORMAL LANGUAGES AND COMPILERS (BREVEGLIERI LUCA ODDONE)", "2026-27"),
            (51001, "052507 - ADVANCED COMPUTER ARCHITECTURES (SILVANO CRISTINA)", "2026-27"),
            (51002, "097683 - MACHINE LEARNING (RESTELLI MARCELLO)", "2026-27"),
            (51003, "088804 - COMPUTER GRAPHICS (GRIBAUDO MARCO)", "2026-27"),
            (51004, "054306 - COMPUTING INFRASTRUCTURES (PALERMO GIANLUCA)", "2026-27"),
            (51005, "095898 - PRINCIPLES OF PROGRAMMING LANGUAGES (PRADELLA MATTEO)", "2026-27"),
            (51006, "051144 - ADVANCED ALGORITHMS AND PARALLEL PROGRAMMING (FERRANDI FABRIZIO)", "2026-27"),
        ]
        let q = query.lowercased()
        return all
            .filter { $0.1.lowercased().contains(q) || q.count < 3 }
            .map { CatalogCourseDTO(id: $0.0, fullname: $0.1, displayname: $0.1, categoryid: 1210, categoryname: $0.2, summary: nil, enrollmentmethods: ["self"]) }
    }

    private static func file(_ name: String, _ path: String = "/", size: Int, daysAgo: Int, id: Int) -> ContentDTO {
        // PDFs point at a public sample so downloads and Quick Look work without WeBeep.
        let url = name.hasSuffix(".pdf")
            ? "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf?course=\(id)&file=\(name)"
            : "https://webeep.polimi.it/webservice/pluginfile.php/\(id)/mod_folder/content/0\(path)\(name)?forcedownload=1"
        return ContentDTO(type: "file", filename: name, filepath: path, filesize: size,
                   fileurl: url,
                   timemodified: Int(Date.now.timeIntervalSince1970) - daysAgo * 86_400, timecreated: nil,
                   mimetype: nil, author: "Docente")
    }

    private static func sections(for id: Int) -> [SectionDTO] {
        func mod(_ mid: Int, _ name: String, _ kind: String, _ contents: [ContentDTO]? = nil, url: String? = nil, desc: String? = nil) -> ModuleDTO {
            ModuleDTO(id: id * 100 + mid, name: name, modname: kind, instance: mid, url: url ?? "https://webeep.polimi.it/mod/\(kind)/view.php?id=\(id * 100 + mid)", description: desc, visible: 1, uservisible: true, contents: contents)
        }
        return [
            SectionDTO(id: id * 10 + 1, name: "{mlang it}Introduzione{mlang}{mlang en}Introduction{mlang}", section: 0, summary: nil, visible: 1, uservisible: true, modules: [
                mod(1, "Annunci", "forum"),
                mod(2, "Benvenuti", "label", desc: "<p>Benvenuti al corso. Le lezioni si tengono in aula <b>D.0.2</b>.</p>"),
                mod(3, "Syllabus", "page", [ContentDTO(type: "file", filename: "index.html", filepath: "/", filesize: 0, fileurl: "https://webeep.polimi.it/webservice/pluginfile.php/\(id)/mod_page/content/index.html", timemodified: nil, timecreated: nil, mimetype: nil, author: nil)]),
            ]),
            SectionDTO(id: id * 10 + 2, name: "Materiali", section: 1, summary: nil, visible: 1, uservisible: true, modules: [
                mod(4, "Lecture 01 – Introduction", "resource", [file("L01_intro.pdf", size: 2_345_678, daysAgo: 12, id: id)]),
                mod(5, "Lecture 02 – Requirements", "resource", [file("L02_requirements.pdf", size: 4_120_000, daysAgo: 8, id: id)]),
                mod(6, "Slides", "folder", [
                    file("L03_design.pptx", size: 18_400_000, daysAgo: 5, id: id),
                    file("L04_architecture.pdf", size: 3_100_000, daysAgo: 2, id: id),
                    file("L05_testing.pdf", size: 2_900_000, daysAgo: 0, id: id),
                    file("2025_L01.pdf", "/Old editions/", size: 1_200_000, daysAgo: 380, id: id),
                ]),
                mod(7, "Exercises", "folder", [
                    file("ex01.pdf", size: 320_000, daysAgo: 9, id: id),
                    file("sol01.pdf", "/Solutions/", size: 410_000, daysAgo: 4, id: id),
                    file("lab-material.zip", size: 52_000_000, daysAgo: 1, id: id),
                ]),
            ]),
            SectionDTO(id: id * 10 + 3, name: "Registrazioni", section: 2, summary: nil, visible: 1, uservisible: true, modules: [
                mod(8, "Recording 2026-09-15", "url", [ContentDTO(type: "url", filename: "Recording", filepath: nil, filesize: 0, fileurl: "https://polimi.cloud.panopto.eu/", timemodified: nil, timecreated: nil, mimetype: nil, author: nil)], url: "https://polimi.cloud.panopto.eu/"),
            ]),
        ]
    }
}
