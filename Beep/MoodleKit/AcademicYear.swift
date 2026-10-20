import Foundation

/// WeBeep categories named "2026-27" are academic years. The Italian academic
/// year rolls over in September.
nonisolated enum AcademicYear {
    static func isAcademicYear(_ categoryName: String) -> Bool {
        startYear(categoryName) != nil
    }

    /// Parsed start years by category name: course lists ask for every course on every render
    /// (and re-render on every sync save), and a regex match per call dominated samples.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var parsed: [String: Int?] = [:]
    nonisolated(unsafe) private static var current: (year: Int, at: Date)?

    /// Start year of an academic-year category, e.g. 2026 for "2026-27".
    static func startYear(_ categoryName: String) -> Int? {
        if let hit = lock.withLock({ parsed[categoryName] }) { return hit }
        let year = categoryName.wholeMatch(of: /(\d{4})-\d{2}/).flatMap { Int($0.1) }
        lock.withLock { parsed[categoryName] = year }
        return year
    }

    /// Start year of the academic year that is current now, cached for a minute.
    static func currentStartYear() -> Int {
        let now = Date.now
        if let hit = lock.withLock({ current }), now.timeIntervalSince(hit.at) < 60 { return hit.year }
        let year = currentStartYear(at: now, calendar: .current)
        lock.withLock { current = (year, now) }
        return year
    }

    /// Start year of the academic year that is current at `date`.
    static func currentStartYear(at date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 2000
        return (comps.month ?? 1) <= 8 ? year - 1 : year
    }

    static func isCurrent(_ categoryName: String) -> Bool {
        startYear(categoryName) == currentStartYear()
    }

    static func isCurrent(_ categoryName: String, at date: Date, calendar: Calendar = .current) -> Bool {
        startYear(categoryName) == currentStartYear(at: date, calendar: calendar)
    }

    /// Semester under way at `date`: the first runs from September, lectures of the second start
    /// in the second half of February at Polimi.
    static func currentSemester(at date: Date = .now, calendar: Calendar = .current) -> Semester {
        let c = calendar.dateComponents([.month, .day], from: date)
        switch (c.month ?? 1, c.day ?? 1) {
        case (3...8, _), (2, 15...): return .second
        default: return .first
        }
    }
}

/// Teaching period of a course. WeBeep does not know it: it comes from the Polimi catalogue
/// (`PolimiCatalogue`) or from the user.
nonisolated enum Semester: Int, Codable, Sendable, CaseIterable {
    case unknown = 0, first = 1, second = 2, annual = 3

    /// Taught during `semester`? Annual courses run in both; unknown in neither.
    func runs(in semester: Semester) -> Bool { self == semester || self == .annual }
}
