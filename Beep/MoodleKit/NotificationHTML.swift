import Foundation

/// Moodle wraps forum-post notifications in a breadcrumb + author table + footer.
/// Keep only the post body when that structure is recognisable.
nonisolated enum NotificationHTML {
    static func cleaned(_ html: String) -> String {
        // Post body lives in <td class="content">…</td>
        if let m = html.firstMatch(of: /<td[^>]*class="[^"]*\bcontent\b[^"]*"[^>]*>(.*?)<\/td>/.dotMatchesNewlines()) {
            let body = String(m.1).trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { return stripAttachmentsFooter(body) }
        }
        // Fallback: drop the breadcrumb paragraph (…» Forum » …) and the footer after the last <hr>.
        var s = html
        s = s.replacing(/<p[^>]*>(?:(?!<\/p>).)*»(?:(?!<\/p>).)*<\/p>/.dotMatchesNewlines(), with: "")
        if let hr = s.range(of: "<hr", options: [.backwards, .caseInsensitive]) {
            let tail = s[hr.lowerBound...]
            if tail.contains("unsubscribe") || tail.contains("Disiscriviti") || tail.contains("post nel contesto") || tail.contains("See this post in context") {
                s = String(s[..<hr.lowerBound])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripAttachmentsFooter(_ body: String) -> String {
        // Moodle appends "<div class="attachments">…" inside content for files; keep it.
        body
    }
}
