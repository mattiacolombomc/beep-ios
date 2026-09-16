import Foundation

/// Turns a `fileurl` from `core_course_get_contents` into a URL that authenticates
/// with the web-service token (Moodle expects `token=` on pluginfile URLs).
///
/// Mirrors myPoliFile's rules and fixes its gap: a file URL that already has a
/// query string but no `forcedownload` also gets `&token=`.
nonisolated enum FileURLTokenizer {
    static func tokenized(_ fileURL: String, type: String, token: String) -> String {
        guard type == "file" else { return fileURL }
        if fileURL.contains("?") {
            return fileURL + "&token=" + token
        }
        return fileURL + "?token=" + token
    }

    /// Stable identity for a remote file, independent of the token.
    static func key(_ fileURL: String) -> String {
        guard let range = fileURL.range(of: "token=") else { return fileURL }
        var trimmed = String(fileURL[..<range.lowerBound])
        if trimmed.hasSuffix("&") || trimmed.hasSuffix("?") { trimmed.removeLast() }
        return trimmed
    }
}
