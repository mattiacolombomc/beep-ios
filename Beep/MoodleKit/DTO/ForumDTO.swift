import Foundation

struct ForumDiscussionsDTO: Decodable, Sendable, Equatable {
    let discussions: [DiscussionDTO]
}

struct DiscussionDTO: Decodable, Sendable, Equatable {
    let id: Int
    let discussion: Int
    let name: String
    let subject: String
    let message: String
    let userfullname: String?
    let created: Int?
    let modified: Int?
    let numreplies: Int?
    let pinned: Bool?
}

struct DiscussionPostsDTO: Decodable, Sendable, Equatable {
    let posts: [PostDTO]
}

struct PostDTO: Decodable, Sendable, Equatable {
    struct Author: Decodable, Sendable, Equatable {
        let fullname: String?
    }
    let id: Int
    let subject: String
    let message: String
    let timecreated: Int?
    let timemodified: Int?
    let author: Author?
    let parentid: Int?
    let hasparent: Bool?
}
