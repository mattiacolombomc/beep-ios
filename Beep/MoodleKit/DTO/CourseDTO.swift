import Foundation

/// One element of `core_enrol_get_users_courses`.
struct CourseDTO: Decodable, Sendable, Equatable {
    let id: Int
    let fullname: String
    let displayname: String
    let shortname: String?
    let category: Int
    let hidden: Bool?
    let isfavourite: Bool?
    let lastaccess: Int?
    let timemodified: Int?
}

/// One element of `core_course_get_categories`.
struct CategoryDTO: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let parent: Int?
}
