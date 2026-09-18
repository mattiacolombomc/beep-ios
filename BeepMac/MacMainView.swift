import SwiftData
import SwiftUI

/// Main window: courses in the sidebar, the selected course on the right.
/// Recent, Activity and Search replace the split view, picked from the toolbar or ⌘1/⌘2/⌘3/⌘F.
struct MacMainView: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(TokenRenewer.self) private var renewer
    @Environment(AppRouter.self) private var router
    @Environment(FileOpener.self) private var opener
    @Environment(\.modelContext) private var context
    @Environment(\.openSettings) private var openSettings
    @State private var selection: Int?

    var body: some View {
        @Bindable var router = router
        content
            .safeAreaInset(edge: .bottom, spacing: 0) { SyncFolderBar() }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Section", selection: $router.selectedTab) {
                        Label("Courses", systemImage: "graduationcap").tag(AppRouter.AppTab.courses)
                        Label("Recent", systemImage: "clock").tag(AppRouter.AppTab.recent)
                        Label("Activity", systemImage: "arrow.down.circle").tag(AppRouter.AppTab.activity)
                        Label("Search", systemImage: "magnifyingglass").tag(AppRouter.AppTab.search)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.titleAndIcon)
                }
                ToolbarItem(placement: .primaryAction) {
                    SyncButton()
                }
            }
            .filePresenters()
            .sheet(isPresented: $router.showNotifications) {
                NotificationsView().frame(minWidth: 480, minHeight: 560)
            }
            // Shared views ask for Settings through the router; on the Mac that's the Settings window.
            .onChange(of: router.showSettings) { _, show in
                guard show else { return }
                router.showSettings = false
                openSettings()
            }
            .onChange(of: router.pending, initial: true) { _, dest in
                guard let dest else { return }
                switch dest {
                case .course(let id):
                    selection = id
                case .file(let key):
                    var d = FetchDescriptor<FileItem>(predicate: #Predicate { $0.key == key })
                    d.fetchLimit = 1
                    if let file = try? context.fetch(d).first { opener.open(file) }
                case .sync:
                    if let client = session.client, let user = session.user { Task { _ = await sync.syncAll(client: client, userID: user.id) } }
                }
                router.pending = nil
            }
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

    @ViewBuilder
    private var content: some View {
        switch router.selectedTab {
        case .courses:
            NavigationSplitView {
                CoursesListView(selection: $selection, isSplit: true)
                    .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
            } detail: {
                if let selection {
                    NavigationStack {
                        CourseDetailView(courseID: selection)
                            .courseRoutes()
                    }
                    .id(selection)
                } else {
                    RecentFilesView()
                }
            }
        case .recent:
            RecentFilesView()
        case .activity:
            ActivityView()
        case .search:
            GlobalSearchView()
        }
    }
}

/// Toolbar sync control: a spinner with progress while running.
struct SyncButton: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        if case .indexing(let done, let total, _) = sync.phase {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("\(done)/\(total)").monospacedDigit().foregroundStyle(.secondary)
            }
            .help("Updating courses…")
        } else {
            Button {
                guard let client = session.client, let user = session.user else { return }
                Task { _ = await sync.syncAll(client: client, userID: user.id) }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Sync Now")
            .disabled(session.client == nil || DemoData.isEnabled)
        }
    }
}
