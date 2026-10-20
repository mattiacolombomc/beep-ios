import Foundation
import Observation
import SwiftData

/// Fills `Course.semester` from the Polimi catalogue after a sync. Cache policy, per course:
/// never looked up → now; unknown → again daily (the manifesto of a new year may not be out
/// yet); known and current year → again weekly (a course moved to the other semester shows up
/// within a week); known and past year → never again, that catalogue is frozen; set by the
/// user → never. Only courses with a code and an academic year are looked up.
@Observable
final class SemesterResolver {
    private let context: ModelContext
    private(set) var isRunning = false
    private var running: Task<Void, Never>?

    init(context: ModelContext) {
        self.context = context
    }

    nonisolated static func needsCheck(semester: Semester, checkedAt: Date?, isCurrentYear: Bool, isManual: Bool, now: Date = .now) -> Bool {
        if isManual { return false }
        guard let checkedAt else { return true }
        let age = now.timeIntervalSince(checkedAt)
        switch (semester, isCurrentYear) {
        case (.unknown, _): return age > 86_400
        case (_, true): return age > 7 * 86_400
        case (_, false): return false
        }
    }

    /// Looks up every course that is due, or every current-year course with `force` (the
    /// "Refresh periods" action). Coalesces: a run in progress is left alone.
    func resolveDue(force: Bool = false) {
        guard running == nil, !DemoData.isEnabled else { return }
        running = Task {
            await run(force: force)
            running = nil
        }
    }

    /// Catalogue lookup for one course now, e.g. after "From the catalogue" in its context menu.
    func resolve(_ course: Course) async {
        guard !DemoData.isEnabled else { return }
        await lookup(course)
        try? context.save()
    }

    private func run(force: Bool) async {
        isRunning = true
        defer { isRunning = false }
        let now = Date.now
        guard let courses = try? context.fetch(FetchDescriptor<Course>()) else { return }
        let due = courses.filter { c in
            guard c.code != nil, c.isAcademicYear, !c.semesterIsManual else { return false }
            if force { return c.isCurrentYear }
            return Self.needsCheck(semester: c.semester, checkedAt: c.semesterCheckedAt, isCurrentYear: c.isCurrentYear, isManual: false, now: now)
        }
        // One request at a time: a handful of 80 KB pages, and no reason to hammer the catalogue.
        for course in due { await lookup(course) }
        try? context.save()
    }

    private func lookup(_ course: Course) async {
        guard let code = course.code, let year = AcademicYear.startYear(course.categoryName) else { return }
        do {
            let found = try await PolimiCatalogue.period(code: code, startYear: year, transport: URLSessionTransport())
            course.semesterCheckedAt = .now
            // No row: keep what we had (a course dropped from the manifesto still ran in its semester).
            if let found { course.semester = found }
        } catch {
            // Offline or server error: nothing recorded, the next sync tries again.
        }
    }
}
