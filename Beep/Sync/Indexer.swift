import Foundation
import SwiftData

/// Upserts Moodle DTOs into the store and reports what changed.
/// Everything runs on the main actor: the store is small (tens of courses,
/// thousands of files) and SwiftData models are main-actor bound in this app.
struct Indexer {
    let context: ModelContext
    let language: String
    let now: () -> Date

    init(context: ModelContext, language: String = Locale.current.language.languageCode?.identifier ?? "en", now: @escaping () -> Date = { .now }) {
        self.context = context
        self.language = language
        self.now = now
    }

    struct CourseDiff: Equatable {
        var inserted: [Int] = []
        var removed: [Int] = []
    }

    struct ContentDiff: Equatable {
        var newFiles: [String] = []
        var updatedFiles: [String] = []
        var removedFiles: [String] = []
    }

    // MARK: Courses

    /// `syncEnabledForNew` decides the default for courses seen for the first time.
    @discardableResult
    func upsertCourses(_ dtos: [CourseDTO], categories: [CategoryDTO], syncEnabledForNew: (CourseDTO, String) -> Bool) throws -> CourseDiff {
        let categoryNames = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let existing = try context.fetch(FetchDescriptor<Course>())
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var diff = CourseDiff()

        for dto in dtos {
            let categoryName = categoryNames[dto.category] ?? ""
            let title = CourseNameParser.parse(dto.displayname, language: language)
            if let course = byID.removeValue(forKey: dto.id) {
                course.fullname = dto.fullname
                course.displayName = dto.displayname
                course.title = title.name
                course.code = title.code
                course.professors = title.professors
                course.categoryID = dto.category
                course.categoryName = categoryName
                course.isFavourite = dto.isfavourite ?? false
                course.isHidden = dto.hidden ?? false
                course.lastAccess = dto.lastaccess.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            } else {
                let course = Course(id: dto.id, fullname: dto.fullname, displayName: dto.displayname,
                                    title: title.name, code: title.code, professors: title.professors,
                                    categoryID: dto.category, categoryName: categoryName,
                                    isFavourite: dto.isfavourite ?? false, isHidden: dto.hidden ?? false,
                                    syncEnabled: syncEnabledForNew(dto, categoryName))
                course.lastAccess = dto.lastaccess.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                context.insert(course)
                diff.inserted.append(dto.id)
            }
        }
        // Courses the user is no longer enrolled in.
        for (id, course) in byID {
            context.delete(course)
            diff.removed.append(id)
        }
        try context.save()
        return diff
    }

    // MARK: Contents

    @discardableResult
    func upsertContents(_ sections: [SectionDTO], for course: Course, token: String) throws -> ContentDiff {
        let stamp = now()
        var diff = ContentDiff()

        var oldSections = Dictionary(uniqueKeysWithValues: course.sections.map { ($0.id, $0) })
        var oldModules: [Int: CourseModule] = [:]
        for s in course.sections { for m in s.modules { oldModules[m.id] = m } }
        var oldFiles = Dictionary(uniqueKeysWithValues: course.files.map { ($0.key, $0) })

        for (sIndex, sDTO) in sections.enumerated() {
            guard sDTO.uservisible ?? true else { continue }
            let section: CourseSection
            if let s = oldSections.removeValue(forKey: sDTO.id) {
                section = s
            } else {
                section = CourseSection(id: sDTO.id, name: "", position: sIndex, summary: nil)
                context.insert(section)
                section.course = course
            }
            section.name = Multilang.resolve(sDTO.name, language: language)
            section.position = sIndex
            section.summary = sDTO.summary?.isEmpty == false ? sDTO.summary : nil

            for (mIndex, mDTO) in sDTO.modules.enumerated() {
                guard mDTO.uservisible ?? true else { continue }
                let module: CourseModule
                if let m = oldModules.removeValue(forKey: mDTO.id) {
                    module = m
                    module.section = section
                } else {
                    module = CourseModule(id: mDTO.id, name: "", modname: mDTO.modname, instance: mDTO.instance,
                                          url: mDTO.url, descriptionHTML: nil, position: mIndex)
                    context.insert(module)
                    module.section = section
                }
                module.name = Multilang.resolve(mDTO.name, language: language)
                module.modname = mDTO.modname
                module.instance = mDTO.instance
                module.url = mDTO.url
                module.descriptionHTML = mDTO.description?.isEmpty == false ? mDTO.description : nil
                module.position = mIndex

                for cDTO in mDTO.contents ?? [] where cDTO.type == "file" {
                    guard let fileurl = cDTO.fileurl else { continue }
                    let key = FileURLTokenizer.key(fileurl)
                    let modified = Date(timeIntervalSince1970: TimeInterval(cDTO.timemodified ?? 0))
                    let remote = FileURLTokenizer.tokenized(fileurl, type: cDTO.type, token: token)
                    if let file = oldFiles.removeValue(forKey: key) {
                        if file.timemodified < modified {
                            diff.updatedFiles.append(key)
                        }
                        file.filename = cDTO.filename
                        file.filepath = cDTO.filepath ?? "/"
                        file.filesize = cDTO.filesize ?? 0
                        file.timemodified = modified
                        file.mimetype = cDTO.mimetype
                        file.remoteURL = remote
                        file.module = module
                    } else {
                        let file = FileItem(key: key, filename: cDTO.filename, filepath: cDTO.filepath ?? "/",
                                            filesize: cDTO.filesize ?? 0, timemodified: modified,
                                            mimetype: cDTO.mimetype, remoteURL: remote, firstSeenAt: stamp)
                        context.insert(file)
                        file.course = course
                        file.module = module
                        diff.newFiles.append(key)
                    }
                }
            }
        }

        for (_, s) in oldSections { context.delete(s) }
        for (_, m) in oldModules { context.delete(m) }
        for (key, f) in oldFiles {
            context.delete(f)
            diff.removedFiles.append(key)
        }
        course.lastIndexedAt = stamp
        if course.lastSeenAt == nil {
            // First index: nothing is "new" yet.
            course.lastSeenAt = stamp
        }
        try context.save()
        return diff
    }

    // MARK: Notifications

    func upsertNotifications(_ dtos: [NotificationDTO]) throws {
        let existing = try context.fetch(FetchDescriptor<WebeepNotification>())
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for dto in dtos {
            let created = Date(timeIntervalSince1970: TimeInterval(dto.timecreated))
            if let n = byID[dto.id] {
                n.read = dto.read ?? n.read
                n.subject = dto.subject
                n.htmlBody = dto.fullmessagehtml ?? dto.fullmessage
            } else {
                context.insert(WebeepNotification(id: dto.id, subject: dto.subject, htmlBody: dto.fullmessagehtml ?? dto.fullmessage,
                                                  contextURL: dto.contexturl, contextName: dto.contexturlname,
                                                  timecreated: created, read: dto.read ?? false))
            }
        }
        try context.save()
    }
}
