import Foundation
import SwiftData
import Testing
@testable import Beep

/// Latency budgets of the Mac window, measured inside the running app with the same signposted
/// intervals Instruments shows ("Open course", "Switch section"). They need a signed-in app with
/// synced courses (they read the user's store, never write it). A failure means an interaction
/// regressed past its budget: profile it before touching the budget.
@MainActor
@Suite(.serialized)
struct InteractionBudgetTests {
    /// 95th percentile of main-thread busy time per interaction, on an idle Mac.
    static let openCourseBudgetMs = 50.0
    static let switchSectionBudgetMs = 50.0

    private func waitForApp() async throws -> AppRouter? {
        for _ in 0..<150 {
            if let router = AppServices.router, AppServices.container != nil, AppServices.session?.client != nil { return router }
            try await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private func p95(_ values: [Double]) -> Double {
        let s = values.sorted()
        return s[min(s.count - 1, max(0, Int((Double(s.count) * 0.95).rounded(.up)) - 1))]
    }

    private func durations(of interaction: Perf.Interaction, steps: [() -> Void]) async throws -> [Double] {
        try await Task.sleep(for: .seconds(2))   // let launch work settle
        Perf.recorded.removeAll()
        for step in steps {
            step()
            try await Task.sleep(for: .milliseconds(900))
        }
        return Perf.recorded.filter { $0.interaction == interaction }.map(\.ms)
    }

    @Test func openingCoursesStaysWithinBudget() async throws {
        guard let router = try await waitForApp() else {
            Issue.record("The app is not signed in: the budget needs real courses."); return
        }
        let context = ModelContext(try #require(AppServices.container))
        var d = FetchDescriptor<Course>(sortBy: [SortDescriptor(\.title)])
        d.fetchLimit = 16
        let ids = try context.fetch(d).filter { !$0.isHidden }.prefix(12).map(\.id)
        try #require(ids.count >= 5)
        router.selectedTab = .courses
        let ms = try await durations(of: .openCourse, steps: ids.map { id in { router.open(.course(id)) } })
        let p = p95(ms)
        print("BUDGET open course p95 \(Int(p)) ms, all \(ms.map { Int($0) })")
        #expect(ms.count >= ids.count - 1, "Every open must produce an interval")
        #expect(p <= Self.openCourseBudgetMs, "Opening a course: p95 \(Int(p)) ms > budget \(Int(Self.openCourseBudgetMs)) ms")
    }

    @Test func switchingSectionsStaysWithinBudget() async throws {
        guard let router = try await waitForApp() else {
            Issue.record("The app is not signed in: the budget needs real courses."); return
        }
        let path: [AppRouter.AppTab] = [.recent, .courses, .activity, .courses, .search, .courses, .recent, .activity, .search, .recent, .courses, .search]
        let ms = try await durations(of: .switchSection, steps: path.map { tab in { router.selectedTab = tab } })
        let p = p95(ms)
        print("BUDGET switch section p95 \(Int(p)) ms, all \(ms.map { Int($0) })")
        #expect(p <= Self.switchSectionBudgetMs, "Switching sections: p95 \(Int(p)) ms > budget \(Int(Self.switchSectionBudgetMs)) ms")
    }
}
