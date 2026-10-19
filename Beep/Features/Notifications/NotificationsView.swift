import SwiftData
import SwiftUI

/// WeBeep popup notifications: refreshed on open, tap to read, mark read on WeBeep too.
/// One sheet: the detail is pushed inside it, not stacked as a second sheet.
struct NotificationsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var context
    @Query(sort: \WebeepNotification.timecreated, order: .reverse) private var notifications: [WebeepNotification]
    @Query private var courses: [Course]
    @State private var selected: WebeepNotification?
    @State private var isLoading = false
    @State private var error: String?

    private var coursesByID: [Int: Course] { Dictionary(courses.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        let byID = coursesByID
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
                        NotificationRow(notification: n, course: n.courseID.flatMap { byID[$0] })
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
            .navigationDestination(item: $selected) { n in
                NotificationDetail(notification: n, course: n.courseID.flatMap { byID[$0] })
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

extension WebeepNotification {
    /// The post's own subject; Moodle prefixes `subject` with the course ("COURSE: subject").
    var postTitle: String { contextName.flatMap { $0.isEmpty ? nil : $0 } ?? subject }

    /// What Moodle put before the post subject, e.g. "Ingegneria Informatica"; nil when the
    /// subject is not in that shape.
    var subjectPrefix: String? {
        guard let ctx = contextName, !ctx.isEmpty, subject.hasSuffix(ctx), subject.count > ctx.count else { return nil }
        let prefix = subject.dropLast(ctx.count).trimmingCharacters(in: CharacterSet(charactersIn: ": \n"))
        return prefix.isEmpty ? nil : prefix
    }
}

/// Course tile, post subject and course name, time on the trailing side, dot while unread.
private struct NotificationRow: View {
    let notification: WebeepNotification
    let course: Course?

    private var origin: String? { course?.title ?? notification.subjectPrefix }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m - 4) {
            if let course {
                CourseTile(monogram: course.monogram, color: course.color)
            } else {
                CourseTile(monogram: "", color: .secondary)
                    .overlay { Image(systemName: "megaphone.fill").foregroundStyle(.white).font(.subheadline) }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(notification.postTitle)
                    .font(notification.read ? .body : .body.weight(.semibold))
                    .lineLimit(2)
                if let origin {
                    Text(origin).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.s)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                Text(notification.timecreated, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                if !notification.read {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                        .accessibilityLabel("Unread")
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .contentShape(.rect)
    }
}

/// The post, with the Moodle chrome (breadcrumb, avatar, footer) stripped; author and date under
/// the title, the course as navigation title.
struct NotificationDetail: View {
    let notification: WebeepNotification
    let course: Course?
    @Environment(\.openURL) private var openURL
    private let parsed: NotificationHTML.Parsed

    init(notification: WebeepNotification, course: Course?) {
        self.notification = notification
        self.course = course
        parsed = NotificationHTML.parse(notification.htmlBody ?? "")
    }

    private var meta: String {
        [parsed.author, notification.timecreated.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        HTMLDocumentView(title: notification.postTitle, meta: meta, bodyHTML: parsed.body)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(course?.title ?? notification.subjectPrefix ?? String(localized: "Notification"))
            .inlineNavigationTitle()
            .toolbar {
                if let s = notification.contextURL, let url = URL(string: s) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Open on WeBeep", systemImage: "safari") { openURL(url) }
                    }
                }
            }
    }
}
