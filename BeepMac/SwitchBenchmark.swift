#if DEBUG || BENCH
import AppKit
import SwiftUI

/// Debug harness (`-benchSwitch`): switches sections on its own and prints how long the main
/// thread stalls after each switch, then quits. Measures the "lag when changing view".
enum SwitchBenchmark {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-benchSwitch") }

    /// `-startTab=search` opens the window on that section (layout checks without clicking).
    static var startTab: AppRouter.AppTab? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-startTab=") }
            .flatMap { AppRouter.AppTab(rawValue: String($0.dropFirst("-startTab=".count))) }
    }

    /// Pings the main queue from a background thread; the delay of each ping is time the
    /// main thread spent busy (layout, view updates, toolbar rebuilds).
    final class StallMonitor: @unchecked Sendable {
        private let lock = NSLock()
        private var total: Double = 0
        private var worst: Double = 0
        private var running = true

        func start() {
            Thread.detachNewThread { [self] in
                while lock.withLock({ running }) {
                    let sent = CACurrentMediaTime()
                    let done = DispatchSemaphore(value: 0)
                    DispatchQueue.main.async { done.signal() }
                    done.wait()
                    let delay = CACurrentMediaTime() - sent
                    lock.withLock {
                        if delay > 0.008 { total += delay }
                        worst = max(worst, delay)
                    }
                    Thread.sleep(forTimeInterval: 0.002)
                }
            }
        }

        func reset() { lock.withLock { total = 0; worst = 0 } }
        func read() -> (total: Double, worst: Double) { lock.withLock { (total, worst) } }
        func stop() { lock.withLock { running = false } }
    }

    @MainActor static func run(router: AppRouter) async {
        let monitor = StallMonitor()
        monitor.start()
        try? await Task.sleep(for: .seconds(6))
        typealias T = AppRouter.AppTab
        let path: [T] = [.recent, .courses, .activity, .courses, .search, .courses, .recent, .activity, .search, .recent]
        var rows: [(String, Double, Double)] = []
        for _ in 0..<2 {
            for tab in path {
                let from = router.selectedTab
                monitor.reset()
                router.selectedTab = tab
                try? await Task.sleep(for: .milliseconds(1200))
                let r = monitor.read()
                rows.append(("\(from.rawValue)->\(tab.rawValue)", r.total * 1000, r.worst * 1000))
            }
        }
        monitor.stop()
        let variant = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-variant=") } ?? "-variant=baseline"
        for (name, total, worst) in rows {
            print(String(format: "BENCH %@ %-22@ stall %6.0f ms  worst %5.0f ms", variant, name, total, worst))
        }
        let avg = rows.map(\.1).reduce(0, +) / Double(rows.count)
        print(String(format: "BENCH %@ AVERAGE stall %.0f ms over %d switches", variant, avg, rows.count))
        fflush(stdout)
        exit(0)
    }
}
#endif
