import SwiftUI

/// Design tokens. One accent (asset `AccentColor`), a fixed 6-hue palette for
/// course identity picked at equal OKLCH lightness, shipped in Display P3.
nonisolated enum Theme {
    static let coursePalette: [Color] = [
        Color(.displayP3, red: 0.20, green: 0.47, blue: 0.90),  // blue
        Color(.displayP3, red: 0.10, green: 0.62, blue: 0.62),  // teal
        Color(.displayP3, red: 0.22, green: 0.64, blue: 0.36),  // green
        Color(.displayP3, red: 0.92, green: 0.55, blue: 0.15),  // orange
        Color(.displayP3, red: 0.90, green: 0.33, blue: 0.50),  // rose
        Color(.displayP3, red: 0.55, green: 0.42, blue: 0.90),  // violet
    ]

    static func courseColor(id: Int) -> Color {
        coursePalette[abs(id) % coursePalette.count]
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 16
        static let l: CGFloat = 24
        static let xl: CGFloat = 32
    }

    static let cardRadius: CGFloat = 16
}

extension Course {
    var color: Color { Theme.courseColor(id: id) }

    /// Short identity like "SE2", "FLC", "FOR", "DB2" from the title initials.
    var monogram: String { CourseMonogram.make(title) }
}

nonisolated enum CourseMonogram {
    private static let skip: Set<String> = ["and", "or", "of", "the", "for", "in", "on", "to", "a", "an",
                                            "e", "di", "del", "della", "dei", "delle", "per", "con", "da", "al", "alla", "ed", "i", "il", "la", "le", "lo", "gli"]

    static func make(_ title: String) -> String {
        let words = title.split(separator: " ").map(String.init)
        var letters = ""
        var suffix = ""
        for w in words {
            if let _ = Int(w) { suffix = w; continue }
            if w.allSatisfy({ "IVX".contains($0) }) && w.count <= 3 { suffix = w; continue }
            if skip.contains(w.lowercased()) { continue }
            if let f = w.first(where: \.isLetter) { letters.append(f.uppercased()) }
        }
        if letters.isEmpty { letters = String(title.prefix(3)).uppercased() }
        let maxLetters = suffix.isEmpty ? 5 : 4
        return String(letters.prefix(maxLetters)) + suffix
    }
}

extension Date {
    /// "Just now" under a minute, otherwise a named relative date ("5 minutes ago", "yesterday").
    var relativeLabel: String {
        if Date.now.timeIntervalSince(self) < 60 { return String(localized: "Just now") }
        return formatted(.relative(presentation: .named))
    }
}

extension Int {
    /// "0 KB", "2,3 MB", "1,2 GB".
    var fileSizeLabel: String {
        self == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}
