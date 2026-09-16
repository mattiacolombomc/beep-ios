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
    /// On-disk folder name; equals `title` unless another course shares it (then "Title (Professors)").
    var folderName: String = ""
    var lastIndexedAt: Date?
    /// Last time the user opened the course; files first seen after this are "new".
    var lastSeenAt: Date?
    var lastAccess: Date?

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

    var isAcademicYear: Bool { AcademicYear.isAcademicYear(categoryName) }
    var isCurrentYear: Bool { AcademicYear.isCurrent(categoryName) }
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

    init(id: Int, subject: String, htmlBody: String?, contextURL: String?, contextName: String?, timecreated: Date, read: Bool) {
        self.id = id
        self.subject = subject
        self.htmlBody = htmlBody
        self.contextURL = contextURL
        self.contextName = contextName
        self.timecreated = timecreated
        self.read = read
    }
}
