import SwiftData
import SwiftUI

/// WeBeep popup notifications: refreshed on open, tap to read, mark read on WeBeep too.
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Query(sort: \WebeepNotification.timecreated, order: .reverse) private var notifications: [WebeepNotification]
    @State private var selected: WebeepNotification?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }
                if notifications.isEmpty && !isLoading {
                    ContentUnavailableView("No notifications", systemImage: "bell", description: Text("WeBeep announcements and messages will show up here."))
                        .listRowBackground(Color.clear)
                }
                ForEach(notifications) { n in
                    Button {
                        selected = n
                        markRead(n)
                    } label: {
                        HStack(alignment: .top, spacing: Theme.Spacing.m - 4) {
                            Circle()
                                .fill(n.read ? Color.clear : Color.accentColor)
                                .frame(width: 8, height: 8)
                                .padding(.top, 7)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(n.subject).font(n.read ? .body : .headline).lineLimit(2)
                                if let ctx = n.contextName, !ctx.isEmpty {
                                    Text(ctx).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Text(n.timecreated, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .groupedList()
            .navigationTitle("Notifications")
            .inlineNavigationTitle()
            .overlay { if isLoading && notifications.isEmpty { ProgressView() } }
            .refreshable { await refresh() }
            .toolbar {
                ToolbarItem(placement: Self.markAllPlacement) {
                    Button("Mark all read") { for n in notifications where !n.read { markRead(n) } }
                        .disabled(!notifications.contains { !$0.read })
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selected) { n in
                NotificationDetail(notification: n)
            }
            .task { await refresh() }
        }
    }

    private static var markAllPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .cancellationAction
        #else
        .leadingBar
        #endif
    }

    private func refresh() async {
        guard let client = session.client, let user = session.user, user.id != 0, !DemoData.isEnabled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dto = try await client.popupNotifications(userID: user.id)
            try Indexer(context: context).upsertNotifications(dto.notifications)
            error = nil
        } catch MoodleError.invalidToken {
            session.signOut()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func markRead(_ n: WebeepNotification) {
        guard !n.read else { return }
        n.read = true
        if let client = session.client, !DemoData.isEnabled {
            Task { try? await client.markNotificationRead(id: n.id) }
        }
    }
}

struct NotificationDetail: View {
    let notification: WebeepNotification
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            HTMLDocumentView(
                title: notification.subject,
                meta: [notification.contextName, notification.timecreated.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "),
                bodyHTML: NotificationHTML.cleaned(notification.htmlBody ?? "")
            )
            .ignoresSafeArea(edges: .bottom)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let s = notification.contextURL, let url = URL(string: s) {
                    // Mac sheets only show the action placements at the bottom.
                    #if os(macOS)
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Open on WeBeep", systemImage: "safari") { openURL(url) }
                    }
                    #else
                    ToolbarItem(placement: .leadingBar) {
                        Button("Open on WeBeep", systemImage: "safari") { openURL(url) }
                    }
                    #endif
                }
            }
        }
        .presentationDetents([.medium, .large])
        #if os(macOS)
        // The web view has no intrinsic size: without a frame the Mac sheet collapses to its toolbar.
        .frame(minWidth: 520, idealWidth: 600, minHeight: 480, idealHeight: 620)
        #endif
    }
}
