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
            Tab("Courses", systemImage: "graduationcap", value: .courses) { CoursesHomeView().syncDrop() }
            Tab("Recent", systemImage: "clock", value: .recent) { RecentFilesView().syncDrop() }
            Tab("Activity", systemImage: "arrow.down.circle", value: .activity) { ActivityView().syncDrop() }
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
        .filePresenters()
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .sheet(isPresented: $router.showNotifications) { NotificationsView() }
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

private extension View {
    /// Inside each tab, so the drop sits above the iPhone tab bar. Not on Search: on iPhone its
    /// field is at the bottom, where the drop would cover it.
    func syncDrop() -> some View {
        overlay(alignment: .bottomTrailing) { SyncDrop() }
    }
}

/// The sync control: a Liquid Glass drop in the bottom trailing corner. A tap on the drop opens
/// the status bar out of it, a tap on the bar syncs; the bar goes back into the drop when the sync
/// and its downloads end, or on a tap outside it. A full-width bar under the lists started syncs
/// from taps meant to scroll.
///
/// The drop never leaves; the bar is inserted next to it in one `GlassEffectContainer`, so the
/// system morphs it out of and back into the drop. Measured on the iPad simulator: swapping the
/// drop and the bar under one `glassEffectID` cut between them in a single frame, and animating
/// one capsule's width undershot it into a squeezed pill at the end of the bouncy spring.
struct SyncDrop: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(AppRouter.self) private var router
    @Namespace private var glass
    @State private var available: CGFloat = 0

    private static let dropSize: CGFloat = 52
    private static let gap: CGFloat = 8
    private var busy: Bool { sync.isRunning || sync.downloads.progress.isBusy }
    /// Shared by the tabs' drops: switching tab keeps it open.
    private var isOpen: Bool { router.syncBarOpen }
    private var barWidth: CGFloat {
        max(160, min(340, available - 2 * Theme.Spacing.m - Self.dropSize - Self.gap))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { available = $0 }
                .allowsHitTesting(false)
            // Tap outside closes it, unless a sync is running: then it stays open until the end
            // and does not block the screen.
            if isOpen && !busy {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { setOpen(false) }
                    .ignoresSafeArea()
            }
            GlassEffectContainer(spacing: 20) {
                HStack(spacing: Self.gap) {
                    if isOpen {
                        Button(action: syncNow) { bar.frame(width: barWidth, height: Self.dropSize).contentShape(.capsule) }
                            .buttonStyle(.plain)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .glassEffectID("bar", in: glass)
                            .accessibilityLabel(Text(title))
                            .accessibilityValue(Text(subtitle))
                            .accessibilityHint("Syncs your courses now")
                    }
                    Button { setOpen(!isOpen) } label: { drop }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("drop", in: glass)
                        .accessibilityLabel(Text(title))
                        .accessibilityValue(Text(subtitle))
                        .accessibilityHint("Shows the sync status")
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: busy) { was, now in
            guard was && !now else { return }
            // Done: the bar shows "Last sync now" for a moment, then goes back into the drop.
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                if !busy { setOpen(false) }
            }
        }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.bouncy) { router.syncBarOpen = open }
    }

    /// Closed: the sync symbol, turning while busy, inside a ring that fills with the progress.
    private var drop: some View {
        ZStack {
            if let fraction {
                Circle().stroke(.quaternary, lineWidth: 2.5)
                Circle().trim(from: 0, to: fraction)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: fraction)
            }
            if case .failed = sync.phase {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate, isActive: busy)
                    .foregroundStyle(.tint)
            }
        }
        .font(.body.weight(.semibold))
        .padding(10)
        .frame(width: 52, height: 52)
        .contentShape(.circle)
    }

    private var fraction: Double? {
        if case .indexing(let done, let total, _) = sync.phase { return total > 0 ? Double(done) / Double(total) : 0 }
        let dl = sync.downloads.progress
        return dl.isBusy ? dl.fraction : nil
    }

    private var bar: some View {
        let dl = sync.downloads.progress
        // No symbol: the drop next to the bar shows it, turning and with the progress ring.
        return HStack(spacing: Theme.Spacing.m - 4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
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
            Spacer(minLength: 0)
            if case .idle = sync.phase, !dl.isBusy {
                Text("Sync").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
    }

    private var title: LocalizedStringKey {
        switch sync.phase {
        case .indexing: "Updating courses…"
        case .failed: "Sync failed"
        case .idle: sync.downloads.progress.isBusy ? "Downloading…" : "Sync now"
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
        guard !sync.isRunning, let client = session.client, let user = session.user else { return }
        Task { _ = await sync.syncAll(client: client, userID: user.id) }
    }
}

