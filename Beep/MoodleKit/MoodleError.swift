import Foundation

/// Errors surfaced by `MoodleClient`. `invalidToken` must trigger a logout.
nonisolated enum MoodleError: Error, Equatable, Sendable {
    case invalidToken
    case server(code: String, message: String)
    case http(status: Int)
    case decoding(String)
    case transport(String)
    /// WeBeep answered with a web page instead of data: down for maintenance (every call is
    /// redirected to `/error/`), or otherwise not itself.
    case unavailable
}

/// What the user reads: `error.localizedDescription`, never `String(describing:)`.
extension MoodleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidToken: String(localized: "Your WeBeep session has expired. Sign in again.")
        case .server(let code, let message): String(localized: "WeBeep reported an error: \(message) (\(code))")
        case .http(let status): String(localized: "WeBeep answered with HTTP \(status).")
        case .decoding: String(localized: "WeBeep's answer could not be read.")
        case .transport(let detail): String(localized: "No connection to WeBeep: \(detail)")
        case .unavailable: String(localized: "WeBeep is not available right now, probably for maintenance. Try again later.")
        }
    }
}

/// Moodle returns errors as HTTP 200 with this envelope.
struct MoodleErrorEnvelope: Decodable, Sendable {
    let exception: String
    let errorcode: String
    let message: String?
}
