import SwiftData
import SwiftUI

/// Main window: courses in the sidebar, the selected course on the right; Recent, Activity and
/// Search are picked from the toolbar or ⌘1/⌘2/⌘3/⌘F.
///
/// Every section stays mounted (`SectionLayer`) and only the visible one shows: rebuilding a
/// section on each switch recreated its split view and lists and re-attached them to the window.
/// Section toolbars and titles follow `isActiveSection`, read only by their small modifiers.
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
        // The folder bar sits below the split view (not as a safe-area inset): the detail
        // column would otherwise extend under it and hide its own bottom insets.
        VStack(spacing: 0) {
            content
            SyncFolderBar()
        }
            .toolbar {
                ToolbarItem(placement: .principal) { SectionPicker() }
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
                #if DEBUG || BENCH
                if SwitchBenchmark.isEnabled { await SwitchBenchmark.run(router: router); return }
                if let tab = SwitchBenchmark.startTab { router.selectedTab = tab; return }
                if ProcessInfo.processInfo.arguments.contains("-benchSync"), let client = session.client, let user = session.user {
                    await TypingBenchmark.runSync { _ = await sync.syncAll(client: client, userID: user.id) }
                    return
                }
                if TypingBenchmark.isEnabled {
                    if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-benchCourse=") }) {
                        selection = Int(arg.dropFirst("-benchCourse=".count))
                    } else if !ProcessInfo.processInfo.arguments.contains("-sidebar") {
                        router.selectedTab = .search
                    }
                    return
                }
                #endif
                // Refresh the index on launch if it's stale (> 15 min) or empty.
                if !DemoData.isEnabled, let client = session.client, let user = session.user, user.id != 0 {
                    if sync.lastSyncAt.map({ Date.now.timeIntervalSince($0) > 15 * 60 }) ?? true {
                        _ = await sync.syncAll(client: client, userID: user.id, trigger: .launch)
                    }
                    await renewer.renewIfNeeded()
                }
            }
    }

    private var content: some View {
        ZStack {
            SectionLayer(tab: .courses) {
                NavigationSplitView {
                    CoursesListView(selection: $selection, isSplit: true)
                        .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
                        .modifier(SidebarToggleWhenActive())
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
            }
            SectionLayer(tab: .recent) { RecentFilesView() }
            SectionLayer(tab: .activity) { ActivityView() }
            SectionLayer(tab: .search) { GlobalSearchView() }
        }
        .modifier(WindowTitle(courseID: selection))
    }
}

/// The hidden Courses split view would keep its sidebar button in the toolbar.
private struct SidebarToggleWhenActive: ViewModifier {
    @Environment(\.isActiveSection) private var isActive
    func body(content: Content) -> some View {
        content.toolbar(removing: isActive ? nil : .sidebarToggle)
    }
}

/// The window title: the open course, or the visible section's name.
private struct WindowTitle: ViewModifier {
    let courseID: Int?
    @Environment(AppRouter.self) private var router
    @Query private var course: [Course]

    init(courseID: Int?) {
        self.courseID = courseID
        let id = courseID ?? -1
        _course = Query(filter: #Predicate<Course> { $0.id == id })
    }

    private var title: String {
        switch router.selectedTab {
        case .courses: course.first?.title ?? String(localized: "Recent")
        case .recent: String(localized: "Recent")
        case .activity: String(localized: "Activity")
        case .search: String(localized: "Search")
        }
    }

    func body(content: Content) -> some View {
        content.navigationTitle(title)
    }
}

/// Only the picker and the layers read `selectedTab`: a switch re-renders them, not the window.
private struct SectionPicker: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        @Bindable var router = router
        Picker("Section", selection: $router.selectedTab) {
            Label("Courses", systemImage: "graduationcap").tag(AppRouter.AppTab.courses)
            Label("Recent", systemImage: "clock").tag(AppRouter.AppTab.recent)
            Label("Activity", systemImage: "arrow.down.circle").tag(AppRouter.AppTab.activity)
            Label("Search", systemImage: "magnifyingglass").tag(AppRouter.AppTab.search)
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
    }
}

/// A section that stays in the window while another one is visible. SwiftUI detaches fully
/// transparent views from the AppKit hierarchy and re-attaches (and lays out) them when they
/// come back, so a hidden section keeps a near-zero opacity instead of 0. The visible one is
/// raised with `zIndex` and receives the clicks; toggling `allowsHitTesting` or
/// `accessibilityHidden` instead made SwiftUI re-attach the hidden lists on every switch.
private struct SectionLayer<Content: View>: View {
    let tab: AppRouter.AppTab
    @ViewBuilder let content: Content
    @Environment(AppRouter.self) private var router

    var body: some View {
        let active = router.selectedTab == tab
        content
            .environment(\.isActiveSection, active)
            .opacity(active ? 1 : 0.001)
            .zIndex(active ? 1 : 0)
    }
}

/// Toolbar sync control: a spinner with progress while running.
struct SyncButton: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        // Reads `isIndexing` (start and end of a sync), never `phase`: a toolbar item whose SwiftUI
        // content changes makes AppKit re-tile the whole toolbar, which happened once per course.
        if sync.isIndexing {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                SyncCounter(sync: sync).frame(width: 44, height: 16)
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

/// "12/56" during a sync. An AppKit label that observes the engine itself: the number changes
/// once per course without touching the SwiftUI toolbar item that hosts it.
private struct SyncCounter: NSViewRepresentable {
    let sync: SyncEngine

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byClipping
        context.coordinator.label = label
        context.coordinator.track()
        return label
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(sync: sync) }

    @MainActor final class Coordinator {
        let sync: SyncEngine
        weak var label: NSTextField?
        init(sync: SyncEngine) { self.sync = sync }

        func track() {
            let text = withObservationTracking {
                if case .indexing(let done, let total, _) = sync.phase { "\(done)/\(total)" } else { "" }
            } onChange: { [weak self] in
                Task { @MainActor in self?.track() }
            }
            label?.stringValue = text
        }
    }
}
