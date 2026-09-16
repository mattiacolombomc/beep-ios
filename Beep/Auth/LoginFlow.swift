import CryptoKit
import Foundation

/// Pure helpers for the official Moodle mobile-app token handshake:
/// `launch.php?service=…&passport=P` → redirect to `moodlemobile://token=<base64>`.
nonisolated enum LoginFlow {
    static let scheme = "moodlemobile"

    static func makePassport() -> String {
        String(format: "%.13f", Double.random(in: 0..<1000))
    }

    static func launchURL(passport: String) -> URL {
        WeBeep.mobileLaunch.appending(queryItems: [
            URLQueryItem(name: "service", value: WeBeep.service),
            URLQueryItem(name: "passport", value: passport),
            URLQueryItem(name: "urlscheme", value: scheme),
        ])
    }

    struct Credentials: Equatable, Sendable {
        let token: String
        let privateToken: String?
        let signatureValid: Bool
    }

    /// Parses `moodlemobile://token=<base64("signature:::token[:::privatetoken]")>`.
    static func parseCallback(_ url: URL, passport: String) -> Credentials? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let raw = url.absoluteString
        guard let range = raw.range(of: "token=") else { return nil }
        var b64 = String(raw[range.upperBound...])
        if let amp = b64.firstIndex(of: "&") { b64 = String(b64[..<amp]) }
        b64 = b64.removingPercentEncoding ?? b64
        guard let data = Data(base64Encoded: b64), let decoded = String(data: data, encoding: .utf8) else { return nil }
        let parts = decoded.components(separatedBy: ":::")
        guard parts.count >= 2, !parts[1].isEmpty else { return nil }
        let expected = Insecure.MD5.hash(data: Data((WeBeep.host.absoluteString + passport).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return Credentials(token: parts[1],
                           privateToken: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil,
                           signatureValid: parts[0].lowercased() == expected)
    }
}
