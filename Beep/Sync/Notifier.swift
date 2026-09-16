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

    static func notifyNewFiles(count: Int, courses: [String]) {
        guard count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "New material on WeBeep")
        let list = courses.prefix(3).joined(separator: ", ")
        content.body = courses.count > 3
            ? String(localized: "\(count) new files in \(list) and \(courses.count - 3) more")
            : String(localized: "\(count) new files in \(list)")
        content.sound = .default
        content.interruptionLevel = .passive
        let request = UNNotificationRequest(identifier: "new-files-\(Int(Date.now.timeIntervalSince1970))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
