import Foundation

/// Errors surfaced by `MoodleClient`. `invalidToken` must trigger a logout.
enum MoodleError: Error, Equatable, Sendable {
    case invalidToken
    case server(code: String, message: String)
    case http(status: Int)
    case decoding(String)
    case transport(String)
}

/// Moodle returns errors as HTTP 200 with this envelope.
struct MoodleErrorEnvelope: Decodable, Sendable {
    let exception: String
    let errorcode: String
    let message: String?
}
