import Foundation

struct PopupNotificationsDTO: Decodable, Sendable, Equatable {
    let notifications: [NotificationDTO]
    let unreadcount: Int?
}

struct NotificationDTO: Decodable, Sendable, Equatable {
    let id: Int
    let subject: String
    let fullmessagehtml: String?
    let fullmessage: String?
    let contexturl: String?
    let contexturlname: String?
    let timecreated: Int
    let read: Bool?
}
