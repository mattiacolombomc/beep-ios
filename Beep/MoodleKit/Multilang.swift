import Foundation

/// WeBeep uses Moodle's multilang filter: `{mlang it}Testo{mlang}{mlang en}Text{mlang}`.
nonisolated enum Multilang {
    /// Returns the variant for `language` (2-letter code), falling back to `en`,
    /// then to the first variant. Text without tags is returned untouched.
    static func resolve(_ text: String, language: String) -> String {
        guard text.contains("{mlang") else { return text }
        var variants: [String: String] = [:]
        var order: [String] = []
        var rest = text[...]
        while let open = rest.range(of: "{mlang ") {
            guard let tagEnd = rest[open.upperBound...].firstIndex(of: "}") else { break }
            let lang = String(rest[open.upperBound..<tagEnd]).trimmingCharacters(in: .whitespaces).lowercased()
            let contentStart = rest.index(after: tagEnd)
            guard let close = rest[contentStart...].range(of: "{mlang}") else { break }
            let content = String(rest[contentStart..<close.lowerBound])
            if variants[lang] == nil { order.append(lang) }
            variants[lang] = (variants[lang] ?? "") + content
            rest = rest[close.upperBound...]
        }
        let wanted = language.prefix(2).lowercased()
        if let hit = variants[String(wanted)] { return hit.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let en = variants["en"] { return en.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let first = order.first, let value = variants[first] { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        return text
    }
}
