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

    /// Stable identity for a remote file, independent of the token and of the module revision.
    ///
    /// Moodle puts the revision of a folder, resource or page in the path of each of its files
    /// (`…/mod_folder/content/19/a.pdf`) and bumps it for all of them on every edit of the module.
    /// Keyed on the raw URL, an untouched file would look deleted and new each time.
    static func key(_ fileURL: String) -> String {
        guard let range = fileURL.range(of: "token=") else { return withoutRevision(fileURL) }
        var trimmed = String(fileURL[..<range.lowerBound])
        if trimmed.hasSuffix("&") || trimmed.hasSuffix("?") { trimmed.removeLast() }
        return withoutRevision(trimmed)
    }

    private static let revisioned = ["/mod_folder/content/", "/mod_resource/content/", "/mod_page/content/"]

    /// Pins the revision segment to `0` rather than dropping it, so that applying the rule to an
    /// already normalized key changes nothing (a sub-folder named "2024" must not be eaten).
    private static func withoutRevision(_ url: String) -> String {
        for marker in revisioned {
            guard let found = url.range(of: marker) else { continue }
            let rest = url[found.upperBound...]
            // No slash after the first segment: it is the file itself (`content/index.html`).
            guard let slash = rest.firstIndex(of: "/") else { return url }
            let revision = rest[..<slash]
            guard !revision.isEmpty, revision.allSatisfy({ $0.isASCII && $0.isNumber }) else { return url }
            return url[..<found.upperBound] + "0" + rest[slash...]
        }
        return url
    }
}
