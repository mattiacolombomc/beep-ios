import Foundation

struct SiteInfoDTO: Decodable, Sendable, Equatable {
    let userid: Int
    let username: String
    let fullname: String
    let siteurl: String
    let userpictureurl: String?
    let lang: String?
}

struct AutologinKeyDTO: Decodable, Sendable, Equatable {
    let key: String
    let autologinurl: String
}
