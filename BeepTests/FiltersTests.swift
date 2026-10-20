import Testing
@testable import Beep

struct FiltersTests {
    @Test func yearFilterRoundTripsThroughItsRawValue() {
        for filter in [YearFilter.all, .current, .past, .year(2025)] {
            #expect(YearFilter(rawValue: filter.rawValue) == filter)
        }
        #expect(YearFilter(rawValue: "year:x") == nil)
        #expect(YearFilter(rawValue: "whatever") == nil)
    }

    @Test func categoryNameFromStartYear() {
        #expect(AcademicYear.categoryName(startYear: 2026) == "2026-27")
        #expect(AcademicYear.categoryName(startYear: 2099) == "2099-00")
    }
}
