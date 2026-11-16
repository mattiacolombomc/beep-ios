import Foundation
import UserNotifications

/// Local notifications for sync results.
enum Notifier {
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do { return try await center.requestAuthorization(options: [.alert, .badge, .sound]) } catch { return false }
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    static func notifySessionExpired() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "WeBeep session expired")
        content.body = String(localized: "Open Beep and sign in again to keep your courses in sync. Your files are safe.")
        content.sound = .default
        content.interruptionLevel = .active
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "session-expired", content: content, trigger: nil))
    }

    /// The number on the app icon (Dock, Home Screen): the unread WeBeep notifications.
    /// A notification can only set it; without this nothing ever lowered it again, so it stayed
    /// on the icon after everything was read, until the app was restarted.
    static func setAppBadge(_ count: Int) {
        guard !DemoData.isEnabled else { return }
        UNUserNotificationCenter.current().setBadgeCount(max(0, count)) { _ in }
    }

    static func notifySyncResults(newFiles: Int, courses: [String], newAnnouncements: Int, unreadAnnouncements: Int) {
        guard newFiles > 0 || newAnnouncements > 0 else { return }
        let content = UNMutableNotificationContent()
        var lines: [String] = []
        if newFiles > 0 {
            let list = courses.prefix(3).joined(separator: ", ")
            lines.append(courses.count > 3
                ? String(localized: "\(newFiles) new files in \(list) and \(courses.count - 3) more")
                : String(localized: "\(newFiles) new files in \(list)"))
        }
        if newAnnouncements > 0 {
            lines.append(String(localized: "\(newAnnouncements) new announcements"))
        }
        content.title = newFiles > 0 ? String(localized: "New material on WeBeep") : String(localized: "New announcements on WeBeep")
        content.body = lines.joined(separator: " · ")
        content.sound = .default
        content.interruptionLevel = .passive
        // The total still unread, not just the ones this sync brought.
        content.badge = NSNumber(value: unreadAnnouncements)
        let request = UNNotificationRequest(identifier: "sync-\(Int(Date.now.timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
