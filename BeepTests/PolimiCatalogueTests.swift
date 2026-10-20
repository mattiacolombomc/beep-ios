import Foundation
import Testing
@testable import Beep

private final class CatalogueAnchor {}

/// Real pages of the Polimi catalogue, saved in October 2026.
private func manifesto(_ code: String) throws -> String {
    let url = try #require(Bundle(for: CatalogueAnchor.self).url(forResource: "manifesto_\(code)", withExtension: "html"))
    return try String(contentsOf: url, encoding: .utf8)
}

struct PolimiCatalogueTests {
    @Test func firstSemesterCourse() throws {
        #expect(PolimiCatalogue.period(in: try manifesto("052537"), code: "052537") == .first)
    }

    @Test func secondSemesterCourse() throws {
        #expect(PolimiCatalogue.period(in: try manifesto("099322"), code: "099322") == .second)
    }

    @Test func otherCodesOnThePageDoNotCount() throws {
        #expect(PolimiCatalogue.period(in: try manifesto("099322"), code: "052537") == nil)
    }

    @Test func majorityWinsAndColumnIsFoundByHeader() {
        let html = """
        <table><tr><th>Periodo</th><th>Codice</th></tr>
        <tr><td>2° sem</td><td><b>012345</b></td></tr>
        <tr><td>Annuale</td><td><b>012345</b></td></tr>
        <tr><td>2° sem</td><td><b>012345</b></td></tr>
        <tr><td>1° trimestre</td><td><b>012345</b></td></tr></table>
        """
        #expect(PolimiCatalogue.period(in: html, code: "012345") == .second)
    }

    @Test func pageWithoutResultsIsUnknown() {
        #expect(PolimiCatalogue.period(in: "<html><body><p>Nessun risultato</p></body></html>", code: "012345") == nil)
    }

    @Test func searchURL() throws {
        let url = PolimiCatalogue.url(code: "052537", startYear: 2026)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.host() == "onlineservices.polimi.it")
        #expect(items.contains(URLQueryItem(name: "aa", value: "2026")))
        #expect(items.contains(URLQueryItem(name: "insegn_ricerca", value: "052537")))
        #expect(items.contains(URLQueryItem(name: "k_cf", value: "-1")))   // "ALL_CF" is a server error
    }
}

struct SemesterTests {
    @Test func currentSemesterByDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Rome")!
        func day(_ month: Int, _ day: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: month, day: day))! }
        #expect(AcademicYear.currentSemester(at: day(10, 20), calendar: cal) == .first)
        #expect(AcademicYear.currentSemester(at: day(1, 15), calendar: cal) == .first)
        #expect(AcademicYear.currentSemester(at: day(2, 10), calendar: cal) == .first)
        #expect(AcademicYear.currentSemester(at: day(2, 20), calendar: cal) == .second)
        #expect(AcademicYear.currentSemester(at: day(5, 5), calendar: cal) == .second)
        #expect(AcademicYear.currentSemester(at: day(9, 1), calendar: cal) == .first)
    }

    @Test func annualRunsInBothSemesters() {
        #expect(Semester.annual.runs(in: .first))
        #expect(Semester.annual.runs(in: .second))
        #expect(!Semester.first.runs(in: .second))
        #expect(!Semester.unknown.runs(in: .first))
    }

    @Test func cachePolicy() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 86_400
        // Never looked up: now.
        #expect(SemesterResolver.needsCheck(semester: .unknown, checkedAt: nil, isCurrentYear: true, isManual: false, now: now))
        // Still unknown: once a day.
        #expect(!SemesterResolver.needsCheck(semester: .unknown, checkedAt: now - 2 * 3600, isCurrentYear: true, isManual: false, now: now))
        #expect(SemesterResolver.needsCheck(semester: .unknown, checkedAt: now - 2 * day, isCurrentYear: false, isManual: false, now: now))
        // Known, current year: once a week.
        #expect(!SemesterResolver.needsCheck(semester: .first, checkedAt: now - 3 * day, isCurrentYear: true, isManual: false, now: now))
        #expect(SemesterResolver.needsCheck(semester: .first, checkedAt: now - 8 * day, isCurrentYear: true, isManual: false, now: now))
        // Known, past year: never again.
        #expect(!SemesterResolver.needsCheck(semester: .second, checkedAt: now - 400 * day, isCurrentYear: false, isManual: false, now: now))
        // Set by the user: never.
        #expect(!SemesterResolver.needsCheck(semester: .first, checkedAt: nil, isCurrentYear: true, isManual: true, now: now))
    }
}
