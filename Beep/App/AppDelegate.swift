import BackgroundTasks
import UIKit

/// Bridges UIKit lifecycle events the SwiftUI app can't receive directly:
/// background URLSession wake-ups and BGTaskScheduler registration.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Wired by BeepApp after the shared objects exist.
    var onBackgroundRefresh: ((BGAppRefreshTask) -> Void)?
    var downloads: DownloadManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundRefresh.register { [weak self] task in
            self?.onBackgroundRefresh?(task)
        }
        return true
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == DownloadManager.sessionIdentifier else { completionHandler(); return }
        downloads?.backgroundCompletionHandler = completionHandler
    }
}
