import Foundation
import Observation
import SwiftData

/// Fills `Course.semester` from the Polimi catalogue after a sync, and as soon as the user
/// picks a semester filter. Cache policy, per course: never looked up → now; unknown → again
/// daily (the manifesto of a new year may not be out yet); known and current year → again
/// weekly (a course moved to the other semester shows up within a week); known and past year →
/// never again, that catalogue is frozen; set by the user → never. Only courses with a code and
/// an academic year are looked up. Progress is published for the first-time panel in the list.
@Observable
final class SemesterResolver {
    private let context: ModelContext
    private(set) var isRunning = false
    /// Lookups done and planned in the current run.
    private(set) var done = 0
    private(set) var total = 0
    /// Lookups of the last run the catalogue could not be reached for.
    private(set) var failed = 0
    /// The run going on, or just failed, was asked for by the user ("Refresh periods").
    private(set) var forced = false
    private var running: Task<Void, Never>?

    /// The list shows the catalogue panel: a run with something to do, or a user-asked run that failed.
    var showsPanel: Bool { (isRunning && total > 0) || (forced && failed > 0) }

    func dismissFailure() {
        failed = 0
        forced = false
    }

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
        guard running == nil else { return }
        running = Task {
            await run(force: force)
            running = nil
        }
    }

    /// Catalogue lookup for one course now, e.g. after "From the catalogue" in its context menu.
    func resolve(_ course: Course) async {
        _ = await lookup(course)
        try? context.save()
    }

    private func run(force: Bool) async {
        isRunning = true
        failed = 0
        forced = force
        defer {
            isRunning = false
            if failed == 0 { forced = false }
        }
        let now = Date.now
        guard let courses = try? context.fetch(FetchDescriptor<Course>()) else { return }
        let due = courses.filter { c in
            guard c.code != nil, c.isAcademicYear, !c.semesterIsManual else { return false }
            if force { return c.isCurrentYear }
            return Self.needsCheck(semester: c.semester, checkedAt: c.semesterCheckedAt, isCurrentYear: c.isCurrentYear, isManual: false, now: now)
        }
        total = due.count
        done = 0
        // One request at a time: a handful of 80 KB pages, and no reason to hammer the catalogue.
        // Saved after each answer so the courses show up in the list one by one.
        for course in due {
            if await !lookup(course) { failed += 1 }
            done += 1
            try? context.save()
        }
    }

    /// False when the catalogue could not be reached (nothing recorded, the next run tries again).
    private func lookup(_ course: Course) async -> Bool {
        guard let code = course.code, let year = AcademicYear.startYear(course.categoryName) else { return true }
        if DemoData.isEnabled {
            // Demo (App Review, screenshots): the real periods, with the real pace, no network.
            try? await Task.sleep(for: .milliseconds(400))
            course.semester = DemoData.periods[code] ?? .unknown
            course.semesterCheckedAt = .now
            return true
        }
        do {
            let found = try await PolimiCatalogue.period(code: code, startYear: year, transport: URLSessionTransport())
            course.semesterCheckedAt = .now
            // No row: keep what we had (a course dropped from the manifesto still ran in its semester).
            if let found { course.semester = found }
            return true
        } catch {
            return false
        }
    }
}
