import Foundation

/// Moodle wraps forum-post notifications in a breadcrumb, an author header and a footer. Two
/// templates seen on WeBeep: the old table (`<td class="content">`) and the 4.x e-mail one, all
/// nested `<div>`s, where `class="content"` holds the post followed by a `commands` block and the
/// "see this post in context" `link` button. Keep only the post body when the structure is
/// recognisable, and pull out the author and the course for the list and the header.
nonisolated enum NotificationHTML {
    struct Parsed: Equatable, Sendable {
        var body: String
        var author: String?
        var courseID: Int?
    }

    static func parse(_ html: String) -> Parsed {
        Parsed(body: cleaned(html), author: author(html), courseID: courseID(html))
    }

    static func cleaned(_ html: String) -> String {
        if let content = element(classed: "content", in: html) {
            var body = String(html[content.inner])
            for cls in ["commands", "link"] {
                while let r = element(classed: cls, in: body) { body.removeSubrange(r.whole) }
            }
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return body }
        }
        // Fallback: drop the breadcrumb (… » Forum » …), the footer after the last <hr> and
        // Moodle's "notification preferences" line.
        var s = html
        if let nav = element(classed: "navbar", in: s) { s.removeSubrange(nav.whole) }
        s = s.replacing(/<p[^>]*>(?:(?!<\/p>).)*(?:»|&raquo;|&#187;)(?:(?!<\/p>).)*<\/p>/.dotMatchesNewlines(), with: "")
        s = s.replacing(/<p[^>]*>\s*<a[^>]*notificationpreferences(?:(?!<\/p>).)*<\/p>/.dotMatchesNewlines(), with: "")
        if let hr = s.range(of: "<hr", options: [.backwards, .caseInsensitive]) {
            let tail = s[hr.lowerBound...]
            if tail.contains("unsubscribe") || tail.contains("Disiscriviti") || tail.contains("post nel contesto") || tail.contains("See this post in context") {
                s = String(s[..<hr.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Who posted: the link in the `author` block ("di <a>Marco Brambilla</a> - sabato…"), or
    /// the initials avatar's title.
    static func author(_ html: String) -> String? {
        if let block = element(classed: "author", in: html) {
            let inner = html[block.inner]
            if let m = inner.firstMatch(of: /<a[^>]*>(.*?)<\/a>/.dotMatchesNewlines()) {
                let name = plain(String(m.1))
                if !name.isEmpty { return name }
            }
        }
        if let m = html.firstMatch(of: /class="userinitials[^"]*"[^>]*\btitle="([^"]+)"/) { return plain(String(m.1)) }
        return nil
    }

    /// The course the notification belongs to, from the first course link in the breadcrumb or body.
    static func courseID(_ html: String) -> Int? {
        html.firstMatch(of: /course\/view\.php\?id=(\d+)/).flatMap { Int($0.1) }
    }

    private static func plain(_ s: String) -> String {
        s.replacing(/<[^>]+>/, with: "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first element whose class attribute has the word `cls`, with its nested same-name
    /// elements balanced: `whole` spans the tags, `inner` the content between them.
    private static func element(classed cls: String, in html: String) -> (whole: Range<String.Index>, inner: Range<String.Index>)? {
        guard let open = try? Regex("<(div|td|p|span|table)\\b[^>]*\\bclass=[\"'][^\"']*\\b\(cls)\\b[^\"']*[\"'][^>]*>"),
              let start = html.firstMatch(of: open),
              let tag = start.output[1].substring,
              let step = try? Regex("</?\(tag)\\b") else { return nil }
        var depth = 1
        var cursor = start.range.upperBound
        while let next = html[cursor...].firstMatch(of: step) {
            depth += html[next.range].hasPrefix("</") ? -1 : 1
            cursor = next.range.upperBound
            if depth == 0 {
                guard let end = html[cursor...].firstIndex(of: ">") else { return nil }
                return (start.range.lowerBound..<html.index(after: end), start.range.upperBound..<next.range.lowerBound)
            }
        }
        return nil
    }
}
