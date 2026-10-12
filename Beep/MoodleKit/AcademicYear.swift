import Foundation

/// WeBeep categories named "2026-27" are academic years. The Italian academic
/// year rolls over in September.
nonisolated enum AcademicYear {
    static func isAcademicYear(_ categoryName: String) -> Bool {
        startYear(categoryName) != nil
    }

    /// Parsed start years by category name: the course list asks for every course on every
    /// render, and a regex match per call showed up in profiles.
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Int?] = [:]

    /// Start year of an academic-year category, e.g. 2026 for "2026-27".
    static func startYear(_ categoryName: String) -> Int? {
        if let hit = cacheLock.withLock({ cache[categoryName] }) { return hit }
        let year: Int? = categoryName.wholeMatch(of: /(\d{4})-\d{2}/).flatMap { Int($0.1) }
        cacheLock.withLock { cache[categoryName] = year }
        return year
    }

    /// Start year of the academic year that is current at `date`.
    static func currentStartYear(at date: Date = .now, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 2000
        return (comps.month ?? 1) <= 8 ? year - 1 : year
    }

    static func isCurrent(_ categoryName: String, at date: Date = .now, calendar: Calendar = .current) -> Bool {
        startYear(categoryName) == currentStartYear(at: date, calendar: calendar)
    }
}
