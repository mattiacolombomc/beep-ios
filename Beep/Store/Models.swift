import Foundation
import SwiftData

@Model
final class Course {
    @Attribute(.unique) var id: Int
    var fullname: String
    var displayName: String
    /// Parsed from `displayName` (see `CourseNameParser`).
    var title: String
    var code: String?
    var professors: String?
    var categoryID: Int
    var categoryName: String
    var isFavourite: Bool
    var isHidden: Bool
    /// Download new files automatically during sync.
    var syncEnabled: Bool
    /// Hidden locally by the user (independent from Moodle's `hidden`).
    var isArchived: Bool = false
    /// On-disk folder of the course (user-renamable); defaults to `title`. Editions of the same
    /// course share it and are kept apart by `editionFolder`.
    var folderName: String = ""
    /// Sub-folder of this edition inside `folderName`: the academic year, plus the professors when
    /// another course has the same title in the same year. Assigned by `assignEditionFolders`.
    var editionFolder: String = ""
    var lastIndexedAt: Date?
    /// Last time the user opened the course; files first seen after this are "new".
    var lastSeenAt: Date?
    var lastAccess: Date?
    /// Files first seen after `lastSeenAt`; maintained by the Indexer and reset when the course is opened,
    /// so list rows and the home header never have to walk the files relationship.
    var newFilesCount: Int = 0
    /// Teaching period (`semester`), looked up in the Polimi catalogue by `SemesterResolver`
    /// unless `semesterIsManual`.
    var semesterRaw: Int = 0
    /// Last catalogue lookup, nil when never done; the resolver decides when to look again.
    var semesterCheckedAt: Date?
    /// Chosen by the user from the context menu: the catalogue never overwrites it.
    var semesterIsManual: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \CourseSection.course) var sections: [CourseSection] = []
    @Relationship(deleteRule: .cascade, inverse: \FileItem.course) var files: [FileItem] = []

    init(id: Int, fullname: String, displayName: String, title: String, code: String?, professors: String?,
         categoryID: Int, categoryName: String, isFavourite: Bool, isHidden: Bool, syncEnabled: Bool) {
        self.id = id
        self.fullname = fullname
        self.displayName = displayName
        self.title = title
        self.code = code
        self.professors = professors
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.isFavourite = isFavourite
        self.isHidden = isHidden
        self.syncEnabled = syncEnabled
    }

    /// Search rule shared by every course search: title, code or professors contain the text,
    /// ignoring case and accents. An empty or blank query matches everything.
    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return title.localizedStandardContains(q)
            || (code?.localizedStandardContains(q) ?? false)
            || (professors?.localizedStandardContains(q) ?? false)
    }

    var isAcademicYear: Bool { AcademicYear.isAcademicYear(categoryName) }
    var isCurrentYear: Bool { AcademicYear.isCurrent(categoryName) }

    nonisolated var semester: Semester {
        get { Semester(rawValue: semesterRaw) ?? .unknown }
        set { semesterRaw = newValue.rawValue }
    }

    /// Where this course's downloads live, relative to the download root: the course folder plus
    /// one sub-folder per academic year ("Data Bases 2/2026-27"), so two editions never mix.
    var folderDirectory: [String] {
        var parts = [folderName.isEmpty ? title : folderName]
        if !editionFolder.isEmpty { parts.append(editionFolder) } else if isAcademicYear { parts.append(categoryName) }
        return parts
    }

    /// Gives every course its `editionFolder`. Deterministic over the whole set, so it can run on
    /// every sync: "2026-27", or "2026-27 (Comai Sara)" when two courses share title and year.
    /// Courses outside an academic year get a sub-folder only when their title is shared.
    nonisolated static func assignEditionFolders(_ courses: [Course]) {
        let groups = Dictionary(grouping: courses) { "\($0.title)\u{1}\($0.categoryName)" }
        for course in courses {
            let shared = (groups["\(course.title)\u{1}\(course.categoryName)"]?.count ?? 0) > 1
            let who = course.professors.flatMap { $0.isEmpty ? nil : $0 } ?? String(course.id)
            let year = course.isAcademicYear ? course.categoryName : ""
            let folder = switch (year.isEmpty, shared) {
            case (false, false): year
            case (false, true): "\(year) (\(who))"
            case (true, true): who
            case (true, false): ""
            }
            if course.editionFolder != folder { course.editionFolder = folder }
        }
    }

    func recountNewFiles() {
        newFilesCount = files.reduce(0) { $0 + ($1.isNew(relativeTo: lastSeenAt) ? 1 : 0) }
    }
}

@Model
final class CourseSection {
    @Attribute(.unique) var id: Int
    var name: String
    var position: Int
    var summary: String?
    var course: Course?
    @Relationship(deleteRule: .cascade, inverse: \CourseModule.section) var modules: [CourseModule] = []

    init(id: Int, name: String, position: Int, summary: String?) {
        self.id = id
        self.name = name
        self.position = position
        self.summary = summary
    }
}

@Model
final class CourseModule {
    @Attribute(.unique) var id: Int
    var name: String
    var modname: String
    var instance: Int?
    var url: String?
    var descriptionHTML: String?
    var position: Int
    var section: CourseSection?
    @Relationship(deleteRule: .cascade, inverse: \FileItem.module) var files: [FileItem] = []

    init(id: Int, name: String, modname: String, instance: Int?, url: String?, descriptionHTML: String?, position: Int) {
        self.id = id
        self.name = name
        self.modname = modname
        self.instance = instance
        self.url = url
        self.descriptionHTML = descriptionHTML
        self.position = position
    }

    var kind: ModuleKind { ModuleKind(rawValue: modname) ?? .other }
}

enum ModuleKind: String, Sendable {
    case resource, folder, url, page, forum, label, lesson, other
}

enum FileState: Int, Codable, Sendable {
    case notDownloaded = 0, queued, downloading, downloaded, failed
}

@Model
final class FileItem {
    /// `fileurl` without the token: stable across syncs.
    @Attribute(.unique) var key: String
    var filename: String
    /// Moodle `filepath`, e.g. "/" or "/Solutions/".
    var filepath: String
    var filesize: Int
    var timemodified: Date
    var mimetype: String?
    var remoteURL: String
    var stateRaw: Int
    var localRelativePath: String?
    /// `timemodified` of the version on disk; older than `timemodified` ⇒ update available.
    var downloadedTimemodified: Date?
    var firstSeenAt: Date
    var lastError: String?
    var course: Course?
    var module: CourseModule?

    init(key: String, filename: String, filepath: String, filesize: Int, timemodified: Date, mimetype: String?, remoteURL: String, firstSeenAt: Date) {
        self.key = key
        self.filename = filename
        self.filepath = filepath
        self.filesize = filesize
        self.timemodified = timemodified
        self.mimetype = mimetype
        self.remoteURL = remoteURL
        self.stateRaw = FileState.notDownloaded.rawValue
        self.firstSeenAt = firstSeenAt
    }

    var state: FileState {
        get { FileState(rawValue: stateRaw) ?? .notDownloaded }
        set { stateRaw = newValue.rawValue }
    }

    var fileExtension: String { (filename as NSString).pathExtension.lowercased() }
    var isDownloaded: Bool { state == .downloaded && localRelativePath != nil }
    var hasUpdate: Bool {
        guard let d = downloadedTimemodified else { return false }
        return d < timemodified
    }
    /// New if first seen after the user last opened the course.
    func isNew(relativeTo lastSeen: Date?) -> Bool {
        guard let lastSeen else { return false }
        return firstSeenAt > lastSeen
    }
}

@Model
final class WebeepNotification {
    @Attribute(.unique) var id: Int
    var subject: String
    var htmlBody: String?
    var contextURL: String?
    var contextName: String?
    var timecreated: Date
    var read: Bool
    /// WeBeep course the notification comes from, read from the course link in its HTML
    /// (`NotificationHTML.courseID`); nil for site-wide messages. The list shows that course's title.
    var courseID: Int?

    init(id: Int, subject: String, htmlBody: String?, contextURL: String?, contextName: String?, timecreated: Date, read: Bool, courseID: Int? = nil) {
        self.id = id
        self.subject = subject
        self.htmlBody = htmlBody
        self.contextURL = contextURL
        self.contextName = contextName
        self.timecreated = timecreated
        self.read = read
        self.courseID = courseID
    }
}
