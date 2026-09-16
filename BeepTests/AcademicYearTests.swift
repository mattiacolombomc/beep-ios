import Foundation
import Testing
@testable import Beep

struct AcademicYearTests {
    let cal = Calendar(identifier: .gregorian)
    func date(_ y: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: 15))! }

    @Test func recognizesCategoryNames() {
        #expect(AcademicYear.isAcademicYear("2026-27"))
        #expect(!AcademicYear.isAcademicYear("CCS"))
        #expect(!AcademicYear.isAcademicYear("Generale"))
        #expect(AcademicYear.startYear("2025-26") == 2025)
    }

    @Test func rolloverInSeptember() {
        #expect(AcademicYear.currentStartYear(at: date(2026, 9), calendar: cal) == 2026)
        #expect(AcademicYear.currentStartYear(at: date(2026, 8), calendar: cal) == 2025)
        #expect(AcademicYear.currentStartYear(at: date(2027, 1), calendar: cal) == 2026)
        #expect(AcademicYear.isCurrent("2026-27", at: date(2026, 9), calendar: cal))
        #expect(!AcademicYear.isCurrent("2025-26", at: date(2026, 9), calendar: cal))
    }
}
