import Foundation

/// Decoded WeBeep course title.
struct CourseTitle: Equatable, Sendable {
    /// Human title, Title Case ("Software Engineering 2").
    var name: String
    /// 6-digit Polimi course code, if present ("054443").
    var code: String?
    /// Professors, Title Case, comma-separated ("Camilli Matteo, Di Nitto Elisabetta").
    var professors: String?
}

/// WeBeep `fullname` conventions seen in the wild:
///   "054443 - SOFTWARE ENGINEERING 2 (CAMILLI MATTEO, DI NITTO ELISABETTA [2026-27])"
///   "ARTIFICIAL NEURAL NETWORKS AND DEEP LEARNING (054307 +056869 BORACCHI-MATTEUCCI) [2026-27]"
///   "{mlang it}Consiglio di Corso di Studi{mlang}{mlang en}Study Programme Board{mlang}"
nonisolated enum CourseNameParser {
    static func parse(_ raw: String, language: String = "en") -> CourseTitle {
        var text = Multilang.resolve(raw, language: language).trimmingCharacters(in: .whitespacesAndNewlines)

        // Trailing "[2026-27]" academic-year tag → drop (category already carries it).
        text = text.replacing(/\s*\[[^\]]*\]\s*$/, with: "")
        text = text.replacing(/\s*\{[^}]*\}\s*$/, with: "")

        var code: String?
        // Leading "054443 - "
        if let m = text.firstMatch(of: /^(\d{6})\s*-\s*/) {
            code = String(m.1)
            text = String(text[m.range.upperBound...])
        }

        var professors: String?
        // Trailing "(...)" group
        if let m = text.firstMatch(of: /\s*\(([^()]*)\)\s*$/) {
            var inside = String(m.1)
            // Codes inside the parentheses: "054307 +056869 BORACCHI-MATTEUCCI"
            if code == nil, let c = inside.firstMatch(of: /\d{6}/) { code = String(c.0) }
            inside = inside.replacing(/\[[^\]]*\]/, with: "")
            inside = inside.replacing(/[\d\s+]*\d{6}[\d\s+]*/, with: " ")
            inside = inside.trimmingCharacters(in: CharacterSet(charactersIn: " -,"))
            if !inside.isEmpty { professors = titleCased(inside, connectors: false) }
            text = String(text[..<m.range.lowerBound])
        }

        let name = titleCased(text.trimmingCharacters(in: .whitespacesAndNewlines))
        return CourseTitle(name: name.isEmpty ? raw : name, code: code, professors: professors)
    }

    /// Title Case for shouty Moodle names; keeps short connectors lowercase and
    /// preserves tokens that already mix case (e.g. "SwiftUI", "IoT").
    /// `connectors: false` capitalises every word (people's names: "Di Nitto").
    static func titleCased(_ s: String, connectors: Bool = true) -> String {
        let lowerWords: Set<String> = ["and", "or", "of", "the", "for", "in", "on", "to", "a", "an",
                                       "e", "di", "del", "della", "dei", "delle", "per", "con", "da", "al", "alla", "ed", "il", "la", "le", "lo", "gli"]
        let words = s.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var out: [String] = []
        for (i, w) in words.enumerated() {
            let isShouty = w == w.uppercased()
            guard isShouty else { out.append(w); continue }
            let lower = w.lowercased()
            if connectors && i > 0 && lowerWords.contains(lower) { out.append(lower); continue }
            // Keep roman numerals and short acronyms as-is (II, AI, ML, UIC, IoT).
            let letters = w.filter(\.isLetter)
            if letters.isEmpty || w.allSatisfy({ "IVXL".contains($0) }) || (connectors && letters.count <= 3) { out.append(w); continue }
            // Hyphenated names: "BORACCHI-MATTEUCCI" → "Boracchi-Matteucci"
            let parts = lower.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            out.append(parts.joined(separator: "-"))
        }
        return out.joined(separator: " ")
    }
}
