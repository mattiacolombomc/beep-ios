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

    @MainActor static func run(set: @escaping (String) -> Void) async {
        let monitor = StallMonitor()
        monitor.start()
        try? await Task.sleep(for: .seconds(5))
        let text = "data bases"
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
