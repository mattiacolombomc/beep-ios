import SwiftData
import SwiftUI

struct MainTabs: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(TokenRenewer.self) private var renewer
    @Environment(AppRouter.self) private var router
    @Environment(FileOpener.self) private var opener
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Courses", systemImage: "graduationcap", value: .courses) { CoursesHomeView() }
            Tab("Recent", systemImage: "clock", value: .recent) { RecentFilesView() }
            Tab("Activity", systemImage: "arrow.down.circle", value: .activity) { ActivityView() }
            Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) { GlobalSearchView() }
        }
        .onChange(of: router.pending) { _, dest in
            guard let dest else { return }
            switch dest {
            case .file(let key):
                var d = FetchDescriptor<FileItem>(predicate: #Predicate { $0.key == key })
                d.fetchLimit = 1
                if let file = try? context.fetch(d).first { opener.open(file) }
                router.pending = nil
            case .sync:
                if let client = session.client, let user = session.user { Task { _ = await sync.syncAll(client: client, userID: user.id) } }
                router.pending = nil
            case .course:
                break // consumed by CoursesHomeView
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { SyncStatusBar() }
        .filePresenters()
        .task {
            // Refresh the index on launch if it's stale (> 15 min) or empty.
            if !DemoData.isEnabled, let client = session.client, let user = session.user, user.id != 0 {
                if sync.lastSyncAt.map({ Date.now.timeIntervalSince($0) > 15 * 60 }) ?? true {
                    _ = await sync.syncAll(client: client, userID: user.id, trigger: .launch)
                }
                await renewer.renewIfNeeded()
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
        // Collapsed tab bar (scrolling down): status only, no button. A sync is heavy and
        // must not start from an accidental tap on the tiny inline pill.
        if placement == .inline {
            inlineStatus
        } else {
            bar
        }
    }

    private var inlineStatus: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: sync.isRunning || sync.downloads.progress.isBusy ? "arrow.triangle.2.circlepath" : "checkmark.circle")
                .font(.caption.weight(.semibold))
                .symbolEffect(.rotate, isActive: sync.isRunning)
            Text(inlineTitle).font(.caption.weight(.medium)).lineLimit(1).monospacedDigit()
                .contentTransition(.numericText())
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.s)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private var bar: some View {
        Button(action: syncNow) {
            let dl = sync.downloads.progress
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
                        if dl.isBusy {
                            ProgressView(value: dl.fraction).progressViewStyle(.circular).controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.body.weight(.semibold))
                        }
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
                        } else if dl.isBusy {
                            ProgressView(value: dl.fraction)
                                .progressViewStyle(.linear)
                                .tint(.accentColor)
                                .animation(.linear(duration: 0.25), value: dl.completedInSession)
                        }
                    }
                }
                Spacer(minLength: 0)
                if case .idle = sync.phase, !dl.isBusy {
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
        case .idle: sync.downloads.progress.isBusy ? "Downloading…" : "Sync now"
        }
    }

    /// Short label for the collapsed tab bar: progress numbers while working, otherwise the last sync.
    private var inlineTitle: String {
        let dl = sync.downloads.progress
        switch sync.phase {
        case .indexing(let done, let total, _): return "\(done)/\(total)"
        case .failed: return String(localized: "Sync failed")
        case .idle: return dl.isBusy ? "\(dl.completedInSession + 1)/\(dl.total)" : subtitle
        }
    }

    private var subtitle: String {
        switch sync.phase {
        case .indexing(let done, let total, let current):
            if let current { return String(localized: "\(done)/\(total) · \(current)") }
            return String(localized: "\(done) of \(total) courses")
        case .failed(let message): return message
        case .idle:
            let dl = sync.downloads.progress
            if dl.isBusy {
                let name = dl.currentFileName ?? ""
                return String(localized: "\(dl.completedInSession + 1)/\(dl.total) · \(name)")
            }
            if let at = sync.lastSyncAt { return String(localized: "Last sync \(at.relativeLabel)") }
            return String(localized: "Never synced")
        }
    }

    private func syncNow() {
        guard let client = session.client, let user = session.user else { return }
        Task { _ = await sync.syncAll(client: client, userID: user.id) }
    }
}
