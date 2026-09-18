import AppKit
import Foundation

/// Periodic checks on the Mac. There is no BGTaskScheduler here: Beep keeps running in
/// the menu bar and syncs on a timer (same "Check frequency" setting as iOS), plus once
/// after the Mac wakes if a check is overdue.
final class MacSyncScheduler {
    /// Set when the app starts; `SyncEngine` asks it to re-arm after every sync.
    static weak var shared: MacSyncScheduler?

    private let session: AppSession
    private let sync: SyncEngine
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(session: AppSession, sync: SyncEngine) {
        self.session = session
        self.sync = sync
    }

    func start() {
        Self.shared = self
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfOverdue() }
        }
        checkIfOverdue()
        reschedule()
    }

    private var enabled: Bool { UserDefaults.standard.bool(forKey: "settings.backgroundRefresh") }
    private var interval: TimeInterval { max(15, UserDefaults.standard.double(forKey: "settings.refreshMinutes")) * 60 }

    /// Arms the next check `interval` from now (called after each sync and when settings change).
    func reschedule() {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func checkIfOverdue() {
        guard enabled else { return }
        let last = sync.lastSyncAt ?? .distantPast
        if Date.now.timeIntervalSince(last) >= interval { tick() }
    }

    private func tick() {
        guard !DemoData.isEnabled, !sync.isRunning,
              UserDefaults.standard.bool(forKey: "onboarding.done"),
              let client = session.client, let user = session.user, user.id != 0 else { reschedule(); return }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { reschedule(); return }
        Task { _ = await sync.syncAll(client: client, userID: user.id, trigger: .background) }
    }
}
