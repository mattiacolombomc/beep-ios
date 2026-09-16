import BackgroundTasks
import Foundation

/// Opportunistic background index refresh. iOS decides when it actually runs.
enum BackgroundRefresh {
    static let identifier = "com.mattiacolombo.Beep.refresh"

    /// The launch handler runs on the main queue, so it can hop into the main actor safely.
    static func register(handler: @escaping @MainActor (BGAppRefreshTask) -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            MainActor.assumeIsolated { handler(task) }
        }
    }

    /// Minimum gap between checks, from Settings ("settings.refreshMinutes", default 120).
    static var intervalMinutes: Double {
        let v = UserDefaults.standard.double(forKey: "settings.refreshMinutes")
        return v > 0 ? v : 120
    }

    static func schedule(after minutes: Double? = nil) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: (minutes ?? intervalMinutes) * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
}
