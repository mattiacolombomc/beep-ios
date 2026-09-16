import Foundation

/// One section of `core_course_get_contents`.
struct SectionDTO: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let section: Int?
    let summary: String?
    let visible: Int?
    let uservisible: Bool?
    let modules: [ModuleDTO]
}

struct ModuleDTO: Decodable, Sendable, Equatable {
    let id: Int
    let name: String
    let modname: String
    let instance: Int?
    let url: String?
    let description: String?
    let visible: Int?
    let uservisible: Bool?
    let contents: [ContentDTO]?
}

struct ContentDTO: Decodable, Sendable, Equatable {
    let type: String
    let filename: String
    let filepath: String?
    let filesize: Int?
    let fileurl: String?
    let timemodified: Int?
    let timecreated: Int?
    let mimetype: String?
    let author: String?
}
