import Foundation

/// `core_course_search_courses`
struct CatalogSearchDTO: Decodable, Sendable, Equatable {
    let total: Int
    let courses: [CatalogCourseDTO]
}

struct CatalogCourseDTO: Decodable, Sendable, Equatable, Identifiable {
    let id: Int
    let fullname: String
    let displayname: String
    let categoryid: Int
    let categoryname: String?
    let summary: String?
    let enrollmentmethods: [String]?
}

/// `enrol_self_enrol_user`
struct EnrolResultDTO: Decodable, Sendable, Equatable {
    struct Warning: Decodable, Sendable, Equatable {
        let warningcode: String?
        let message: String?
    }
    let status: Bool
    let warnings: [Warning]?
}
