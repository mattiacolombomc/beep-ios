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

/// Toolbar sync control: the glass "Sync Now" button; while syncing the same button becomes a
/// progress bar with the n/N counter (click it to open Activity), then turns back into the button.
/// Its SwiftUI content changes only when a sync starts or ends (`isIndexing`): the bar and the
/// number are AppKit views that follow the engine themselves, so the toolbar is never re-tiled
/// once per course.
struct SyncButton: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button {
            if sync.isIndexing {
                router.selectedTab = .activity
            } else if let client = session.client, let user = session.user {
                Task { _ = await sync.syncAll(client: client, userID: user.id) }
            }
        } label: {
            if sync.isIndexing {
                SyncProgressLabel(sync: sync)
                    .frame(width: 128, height: 18)
            } else {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .help(sync.isIndexing ? "Updating courses… Click to see the activity." : "Sync Now")
        .disabled(!sync.isIndexing && (session.client == nil || DemoData.isEnabled))
        .animation(.smooth, value: sync.isIndexing)
    }
}

/// Progress bar and "12/56" counter of a running sync, drawn by AppKit and updated from the
/// engine directly: the SwiftUI toolbar item that hosts it does not change once per course.
private struct SyncProgressLabel: NSViewRepresentable {
    let sync: SyncEngine

    func makeNSView(context: Context) -> NSStackView {
        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.isIndeterminate = false
        bar.controlSize = .small
        bar.minValue = 0
        bar.maxValue = 1
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let stack = NSStackView(views: [bar, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        context.coordinator.bar = bar
        context.coordinator.label = label
        context.coordinator.track()
        return stack
    }

    func updateNSView(_ nsView: NSStackView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(sync: sync) }

    @MainActor final class Coordinator {
        let sync: SyncEngine
        weak var bar: NSProgressIndicator?
        weak var label: NSTextField?
        init(sync: SyncEngine) { self.sync = sync }

        func track() {
            let (done, total) = withObservationTracking {
                if case .indexing(let done, let total, _) = sync.phase { (done, total) } else { (0, 0) }
            } onChange: { [weak self] in
                Task { @MainActor in self?.track() }
            }
            label?.stringValue = total > 0 ? "\(done)/\(total)" : ""
            if let bar {
                let target = total > 0 ? Double(done) / Double(total) : 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    bar.animator().doubleValue = target
                }
            }
        }
    }
}
