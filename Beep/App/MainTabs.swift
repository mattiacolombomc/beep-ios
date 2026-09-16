import SwiftUI

struct MainTabs: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @State private var showActivity = false

    var body: some View {
        TabView {
            Tab("Courses", systemImage: "graduationcap") { CoursesHomeView() }
            Tab("Recent", systemImage: "clock") { RecentFilesView() }
            Tab("Activity", systemImage: "arrow.down.circle") { ActivityView() }
            Tab("Search", systemImage: "magnifyingglass", role: .search) { GlobalSearchView() }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { SyncStatusBar() }
        .filePresenters()
        .task {
            // Refresh the index on launch if it's stale (> 15 min) or empty.
            if let client = session.client, let user = session.user, user.id != 0 {
                if sync.lastSyncAt.map({ Date.now.timeIntervalSince($0) > 15 * 60 }) ?? true {
                    _ = await sync.syncAll(client: client, userID: user.id)
                }
            }
        }
    }
}

/// Persistent sync control above the tab bar (like Music's Now Playing).
struct SyncStatusBar: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: syncNow) {
            HStack(spacing: Theme.Spacing.m - 4) {
                ZStack {
                    switch sync.phase {
                    case .indexing(let done, let total, _):
                        ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                    case .failed:
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    case .idle:
                        Image(systemName: "arrow.triangle.2.circlepath").font(.body.weight(.semibold))
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if placement != .inline {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                            .contentTransition(.numericText())
                        if case .indexing(let done, let total, _) = sync.phase {
                            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                                .progressViewStyle(.linear)
                                .tint(.accentColor)
                                .animation(.linear(duration: 0.25), value: done)
                        }
                    }
                }
                Spacer(minLength: 0)
                if case .idle = sync.phase {
                    Text("Sync").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(sync.isRunning)
        .accessibilityLabel(Text(title))
        .accessibilityHint("Syncs your courses now")
    }

    private var title: LocalizedStringKey {
        switch sync.phase {
        case .indexing: "Updating courses…"
        case .failed: "Sync failed"
        case .idle: "Sync now"
        }
    }

    private var subtitle: String {
        switch sync.phase {
        case .indexing(let done, let total, let current):
            if let current { return String(localized: "\(done)/\(total) · \(current)") }
            return String(localized: "\(done) of \(total) courses")
        case .failed(let message): return message
        case .idle:
            if let at = sync.lastSyncAt { return String(localized: "Last sync \(at.relativeLabel)") }
            return String(localized: "Never synced")
        }
    }

    private func syncNow() {
        guard let client = session.client, let user = session.user else { return }
        Task { _ = await sync.syncAll(client: client, userID: user.id) }
    }
}
