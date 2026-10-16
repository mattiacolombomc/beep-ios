import Foundation
import os

/// Signposted intervals around the interactions with a latency budget (see BeepTests and
/// BeepMacTests): they show up in Instruments (Points of Interest) and XCTOSSignpostMetric.
/// An interval ends when the main run loop is about to sleep, i.e. once the UI has finished
/// updating, laying out and committing the frame: its duration is the time the app was busy.
enum Perf {
    static let subsystem = "com.mattiacolombo.Beep"
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    enum Interaction: String {
        case openCourse = "Open course"
        case switchSection = "Switch section"
    }

    /// Starts an interval now and ends it when the main thread next goes idle. Callable from any
    /// context (the widget shares AppRouter); does nothing off the main thread.
    nonisolated static func measure(_ interaction: Interaction) {
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated { begin(interaction) }
    }

    #if DEBUG
    /// Durations (ms) of finished intervals, for the performance tests.
    @MainActor static var recorded: [(interaction: Interaction, ms: Double)] = []
    #endif

    @MainActor private static func begin(_ interaction: Interaction) {
        #if DEBUG
        let started = ContinuousClock.now
        #endif
        let state: OSSignpostIntervalState = switch interaction {
        case .openCourse: signposter.beginInterval("Open course", id: signposter.makeSignpostID())
        case .switchSection: signposter.beginInterval("Switch section", id: signposter.makeSignpostID())
        }
        endWhenIdle {
            switch interaction {
            case .openCourse: signposter.endInterval("Open course", state)
            case .switchSection: signposter.endInterval("Switch section", state)
            }
            #if DEBUG
            let d = ContinuousClock.now - started
            recorded.append((interaction, Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15))
            #endif
        }
    }

    /// Runs `body` once, the next time the main run loop is about to wait for events. The first
    /// pass is skipped: the change that starts an interval is still being processed in it.
    @MainActor private static func endWhenIdle(_ body: @escaping () -> Void) {
        var passes = 0
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { observer, _ in
            passes += 1
            guard passes >= 2 else { return }
            body()
            CFRunLoopObserverInvalidate(observer)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}

