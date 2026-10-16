import AppKit
import QuartzCore
import SwiftUI

// Feedback repro (macOS 26/27): typing in `.searchable` re-evaluates the content of an unrelated
// toolbar `Menu` on every keystroke and re-tiles the toolbar; a plain TextField in the content
// with the same state does not touch the toolbar.
//
// Run the binary with:
//   -searchable   types 10 characters into `.searchable`
//   -textfield    types 10 characters into a TextField bound to the same state
//   -hidden       toggles ToolbarContent.hidden(_:) on an unrelated item 10 times
// It prints how many times the toolbar Menu's items were evaluated and the main-thread time.

@MainActor enum Probe { static var menuEvaluations = 0 }

final class StallMonitor: @unchecked Sendable {
    private let lock = NSLock(); private var total = 0.0; private var running = true
    func start() {
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let sent = CACurrentMediaTime(); let s = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { s.signal() }; s.wait()
                let d = CACurrentMediaTime() - sent
                lock.withLock { if d > 0.004 { total += d } }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }
    func take() -> Double { lock.withLock { let t = total; total = 0; return t } }
}

@main
struct ToolbarRebuildApp: App {
    var body: some Scene {
        Window("Toolbar rebuild", id: "main") { ContentView().frame(minWidth: 800, minHeight: 400) }
    }
}

struct ContentView: View {
    @State private var query = ""
    @State private var hideExtra = false
    private let mode = ProcessInfo.processInfo.arguments.first { ["-searchable", "-textfield", "-hidden"].contains($0) } ?? "-searchable"

    var body: some View {
        content
            .toolbar {
                ToolbarItem {
                    Menu("More") {
                        ForEach(0..<20) { i in Button(label(i)) {} }
                    }
                }
                ToolbarItem { Button("Share", systemImage: "square.and.arrow.up") {} }
                ToolbarItem { Button("Extra", systemImage: "star") {} }.hidden(hideExtra)
            }
            .task { await run() }
    }

    @ViewBuilder private var content: some View {
        if mode == "-textfield" {
            VStack { TextField("Search", text: $query).padding(); List(0..<50) { Text("Row \($0)") } }
        } else {
            List(0..<50) { Text("Row \($0)") }.searchable(text: $query)
        }
    }

    private func label(_ i: Int) -> String {
        Probe.menuEvaluations += 1
        return "Item \(i)"
    }

    private func run() async {
        guard ProcessInfo.processInfo.arguments.contains(where: { ["-searchable", "-textfield", "-hidden"].contains($0) }) else { return }
        let monitor = StallMonitor(); monitor.start()
        try? await Task.sleep(for: .seconds(2))
        _ = monitor.take()
        let before = Probe.menuEvaluations
        for i in 0..<10 {
            if mode == "-hidden" { hideExtra.toggle() } else { query.append(Character(UnicodeScalar(97 + i)!)) }
            try? await Task.sleep(for: .milliseconds(400))
        }
        let busy = monitor.take() * 1000
        print("\(mode): toolbar Menu items evaluated \(Probe.menuEvaluations - before) times (20 items, 10 changes); main thread busy \(Int(busy)) ms")
        fflush(stdout)
        exit(0)
    }
}
