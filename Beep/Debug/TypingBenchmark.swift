#if DEBUG || BENCH
import QuartzCore
import SwiftUI

/// Measurement harness (`-benchTyping`, with `-startTab=search` on the Mac): types a query one
/// character at a time and prints how long the main thread stalls after each keystroke.
enum TypingBenchmark {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-benchTyping") }

    final class StallMonitor: @unchecked Sendable {
        private let lock = NSLock()
        private var total: Double = 0, worst: Double = 0, running = true
        func start() {
            Thread.detachNewThread { [self] in
                while lock.withLock({ running }) {
                    let sent = CACurrentMediaTime()
                    let done = DispatchSemaphore(value: 0)
                    DispatchQueue.main.async { done.signal() }
                    done.wait()
                    let d = CACurrentMediaTime() - sent
                    lock.withLock { if d > 0.008 { total += d }; worst = max(worst, d) }
                    Thread.sleep(forTimeInterval: 0.002)
                }
            }
        }
        func reset() { lock.withLock { total = 0; worst = 0 } }
        func read() -> (Double, Double) { lock.withLock { (total, worst) } }
    }

    /// Runs named steps 1.2 s apart and prints the main-thread stall after each one.
    @MainActor static func runSteps(_ label: String, _ steps: [(String, () -> Void)]) async {
        let monitor = StallMonitor()
        monitor.start()
        try? await Task.sleep(for: .seconds(5))
        var all: [Double] = []
        for (name, step) in steps {
            monitor.reset()
            step()
            try? await Task.sleep(for: .milliseconds(1200))
            let (t, w) = monitor.read()
            all.append(t * 1000)
            print(String(format: "STEP %@ %-40@ stall %5.0f ms worst %5.0f ms", label, name, t * 1000, w * 1000))
        }
        let sorted = all.sorted()
        print(String(format: "STEP %@ MEDIAN %.0f ms MAX %.0f ms", label, sorted[sorted.count / 2], sorted.last ?? 0))
        fflush(stdout)
        exit(0)
    }

    /// `-benchSync`: runs one real sync and prints the main-thread stalls while it runs.
    @MainActor static func runSync(_ work: () async -> Void) async {
        let monitor = StallMonitor()
        monitor.start()
        try? await Task.sleep(for: .seconds(3))
        let started = CACurrentMediaTime()
        let sampler = Task { @MainActor in
            var windows: [Double] = []
            while !Task.isCancelled {
                monitor.reset()
                try? await Task.sleep(for: .milliseconds(500))
                windows.append(monitor.read().0 * 1000)
            }
            return windows
        }
        await work()
        let finished = CACurrentMediaTime() - started
        print("SYNCDONE"); fflush(stdout)
        // Keep sampling after the sync: the end of a sync (Spotlight, widgets, the toolbar) is
        // where the UI stalled.
        try? await Task.sleep(for: .seconds(5))
        sampler.cancel()
        let windows = await sampler.value
        print("SYNC finished at \(String(format: "%.1f", finished)) s; stalled ms per half second: \(windows.map { Int($0) })")
        let busy = windows.filter { $0 > 100 }.count
        print(String(format: "SYNC took %.1f s, %d half-second windows, %d with >100 ms stalled, worst window %.0f ms, total stalled %.0f ms",
                     CACurrentMediaTime() - started, windows.count, busy, windows.max() ?? 0, windows.reduce(0, +)))
        fflush(stdout)
        exit(0)
    }

    @MainActor static func run(set: @escaping (String) -> Void) async {
        let monitor = StallMonitor()
        monitor.start()
        try? await Task.sleep(for: .seconds(5))
        let text = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-text=") }.map { String($0.dropFirst(6)) } ?? "data bases"
        var typed = ""
        let variant = ProcessInfo.processInfo.arguments.first { $0.hasPrefix("-variant=") } ?? "-variant=base"
        var all: [Double] = []
        for _ in 0..<2 {
            typed = ""
            set(typed)
            try? await Task.sleep(for: .milliseconds(800))
            for ch in text {
                typed.append(ch)
                monitor.reset()
                set(typed)
                try? await Task.sleep(for: .milliseconds(600))
                let (t, w) = monitor.read()
                all.append(t * 1000)
                print(String(format: "TYPE %@ %-12@ stall %5.0f ms worst %5.0f ms", variant, "\"\(typed)\"", t * 1000, w * 1000))
            }
        }
        let sorted = all.sorted()
        print(String(format: "TYPE %@ MEDIAN %.0f ms MAX %.0f ms", variant, sorted[sorted.count / 2], sorted.last ?? 0))
        fflush(stdout)
        exit(0)
    }
}
#endif
