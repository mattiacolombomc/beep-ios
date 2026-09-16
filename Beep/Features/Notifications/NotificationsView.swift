import SwiftData
import SwiftUI

/// WeBeep popup notifications. Full read/mark-read flow lands in M3.
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WebeepNotification.timecreated, order: .reverse) private var notifications: [WebeepNotification]

    var body: some View {
        NavigationStack {
            List {
                if notifications.isEmpty {
                    ContentUnavailableView("No notifications", systemImage: "bell", description: Text("WeBeep announcements and messages will show up here."))
                        .listRowBackground(Color.clear)
                }
                ForEach(notifications) { n in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack {
                            if !n.read { Circle().fill(Color.accentColor).frame(width: 8, height: 8) }
                            Text(n.subject).font(n.read ? .body : .headline).lineLimit(2)
                        }
                        Text(n.timecreated, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
