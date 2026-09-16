import Foundation
import Observation
import SwiftData

/// Cross-cutting navigation requests (Spotlight, widgets, App Intents, URLs).
/// Views observe `pending` and consume it.
@Observable
final class AppRouter {
    enum Destination: Equatable {
        case course(Int)
        case file(String)
        case sync
    }

    var pending: Destination?
    /// Tab to select when a destination arrives.
    var selectedTab: AppTab = .courses

    enum AppTab: String { case courses, recent, activity, search }

    /// beep://course/<id>, beep://file/<base64url key>, beep://sync
    func handle(url: URL) {
        guard url.scheme == "beep" else { return }
        switch url.host() {
        case "course":
            if let id = Int(url.lastPathComponent) { open(.course(id)) }
        case "file":
            if let data = Data(base64URLEncoded: url.lastPathComponent), let key = String(data: data, encoding: .utf8) { open(.file(key)) }
        case "sync":
            open(.sync)
        default: break
        }
    }

    func open(_ destination: Destination) {
        selectedTab = .courses
        pending = destination
    }

    static func fileURL(key: String) -> URL {
        URL(string: "beep://file/\(Data(key.utf8).base64URLEncodedString())")!
    }
    static func courseURL(id: Int) -> URL { URL(string: "beep://course/\(id)")! }
}

extension Data {
    init?(base64URLEncoded s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b.append("=") }
        self.init(base64Encoded: b)
    }
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
