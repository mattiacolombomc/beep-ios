import SwiftData
import SwiftUI

/// Main window: courses in the sidebar, the selected course on the right; Recent, Activity and
/// Search are picked from the toolbar or ⌘1/⌘2/⌘3/⌘F.
///
/// Every section stays mounted (`SectionLayer`) and only the visible one shows: rebuilding a
/// section on each switch recreated its split view and lists and re-attached them to the window.
/// Section toolbars follow `@ActiveSection`, read only by their small modifiers.
struct MacMainView: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(TokenRenewer.self) private var renewer
    @Environment(AppRouter.self) private var router
    @Environment(FileOpener.self) private var opener
    @Environment(\.modelContext) private var context
    @Environment(\.openSettings) private var openSettings
    /// The open course. A reference type read only by the Courses split view and the title: as
    /// `@State` here, opening a course re-rendered the whole window and re-ran every section's query.
    @State private var courseSelection = CourseSelection()
    /// What the toolbar's search, Select and "…" act on, offered by the screens.
    @State private var toolbarModel = WindowToolbarModel()

    var body: some View {
        @Bindable var router = router
        // The folder bar sits below the split view (not as a safe-area inset): the detail
        // column would otherwise extend under it and hide its own bottom insets.
        VStack(spacing: 0) {
            content
            SyncFolderBar()
        }
            .toolbar { MainToolbar() }
            .environment(toolbarModel)
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
                    courseSelection.id = id
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
                if ProcessInfo.processInfo.arguments.contains("-benchOpenCourses") {
                    var d = FetchDescriptor<Course>(sortBy: [SortDescriptor(\.title)])
                    d.fetchLimit = 12
                    let ids = ((try? context.fetch(d)) ?? []).filter { !$0.isHidden }.map { ($0.id, $0.title) }
                    let steps: [(String, () -> Void)] = ids.prefix(10).map { item in (item.1, { courseSelection.id = item.0 }) }
                    await TypingBenchmark.runSteps("open", steps)
                    return
                }
                if ProcessInfo.processInfo.arguments.contains("-benchSearchCourses") {
                    let steps: [(String, () -> Void)] = (0..<10).map { i in
                        i % 2 == 0 ? ("courses->search", { router.selectedTab = .search }) : ("search->courses", { router.selectedTab = .courses })
                    }
                    await TypingBenchmark.runSteps("tabs", steps)
                    return
                }
                if ProcessInfo.processInfo.arguments.contains("-benchSync"), let client = session.client, let user = session.user {
                    await TypingBenchmark.runSync { _ = await sync.syncAll(client: client, userID: user.id) }
                    return
                }
                if TypingBenchmark.isEnabled {
                    if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-benchCourse=") }) {
                        courseSelection.id = Int(arg.dropFirst("-benchCourse=".count))
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
            SectionLayer(tab: .courses) { CoursesSplit(selection: courseSelection) }
            SectionLayer(tab: .recent) { RecentFilesView() }
            SectionLayer(tab: .activity) { ActivityView() }
            SectionLayer(tab: .search) { GlobalSearchView() }
        }
        .modifier(WindowTitle())
    }
}

/// The open course in the Mac window, and whether the course list is shown.
@Observable
final class CourseSelection {
    var id: Int? {
        didSet { if id != oldValue, id != nil { Perf.measure(.openCourse) } }
    }
    var columns: NavigationSplitViewVisibility = .all
}

/// Courses list in the sidebar, the open course (or Recent) on the right.
private struct CoursesSplit: View {
    let selection: CourseSelection

    var body: some View {
        @Bindable var selection = selection
        NavigationSplitView(columnVisibility: $selection.columns) {
            CoursesListView(selection: $selection.id, isSplit: true)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 460)
                // Its own course-list button, present in every section (`SidebarToolbar`).
                .toolbar(removing: .sidebarToggle)
                .toolbar { SidebarToolbar(courses: selection) }
        } detail: {
            if let id = selection.id {
                // No `.id(id)`: recreating the stack per course removed and re-added its toolbar
                // items (menu, search field) on every open. The screen resets itself on course change.
                NavigationStack {
                    CourseDetailView(courseID: id)
                        .courseRoutes()
                }
            } else {
                RecentFilesView()
            }
        }
    }
}

/// No title in the toolbar: the picker names the section and the course header names the
/// course. A title that changed on every course opened made AppKit re-tile the toolbar each time.
/// The window keeps the app name for the Window menu and Mission Control.
private struct WindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationTitle("Beep")
            .toolbar(removing: .title)
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
            .environment(\.sectionTab, tab)
            .opacity(active ? 1 : 0.001)
            .zIndex(active ? 1 : 0)
    }
}

/// Toolbar sync control: the glass "Sync Now" button; while syncing the same button widens into
/// a progress bar with the n/N counter (click it to open Activity), then shrinks back.
/// The label is one AppKit view that never changes in SwiftUI: it follows the engine itself and
/// animates its width constraint, which the toolbar and its glass follow frame by frame. A
/// SwiftUI label swapped by `if` resized the item in a single frame.
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
            SyncButtonLabel(sync: sync)
        }
        .accessibilityLabel(sync.isIndexing ? "Updating courses…" : "Sync Now")
        .help(sync.isIndexing ? "Updating courses… Click to see the activity." : "Sync Now")
        .disabled(!sync.isIndexing && (session.client == nil || DemoData.isEnabled))
    }
}

/// The sync icon, and the progress bar with its "12/56" counter, in one AppKit view whose width
/// is animated between the two (see `SyncButton`).
private struct SyncButtonLabel: NSViewRepresentable {
    let sync: SyncEngine

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.triangle.2.circlepath",
                                              accessibilityDescription: String(localized: "Sync Now"))!)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        icon.contentTintColor = .controlTextColor
        let bar = NSProgressIndicator()
        bar.style = .bar
        bar.isIndeterminate = false
        bar.controlSize = .small
        bar.minValue = 0
        bar.maxValue = 1
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        // Control text, like the toolbar's icons: label and secondary label colours fade almost
        // to invisible inside a glass toolbar button.
        label.textColor = .controlTextColor
        label.alignment = .right
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        let progress = NSStackView(views: [bar, label])
        progress.orientation = .horizontal
        progress.spacing = 6
        progress.alignment = .centerY
        for v in [icon, progress] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        let width = container.widthAnchor.constraint(equalToConstant: Coordinator.iconWidth)
        NSLayoutConstraint.activate([
            width,
            container.heightAnchor.constraint(equalToConstant: 18),
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            progress.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            progress.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        let c = context.coordinator
        c.width = width
        c.icon = icon
        c.progress = progress
        c.bar = bar
        c.label = label
        c.track(animated: false)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(sync: sync) }

    @MainActor final class Coordinator {
        static let iconWidth: CGFloat = 20
        static let progressWidth: CGFloat = 128
        let sync: SyncEngine
        weak var width: NSLayoutConstraint?
        weak var icon: NSImageView?
        weak var progress: NSView?
        weak var bar: NSProgressIndicator?
        weak var label: NSTextField?
        private var showsProgress: Bool?
        init(sync: SyncEngine) { self.sync = sync }

        func track(animated: Bool = true) {
            let (indexing, done, total) = withObservationTracking {
                if case .indexing(let done, let total, _) = sync.phase { (sync.isIndexing, done, total) } else { (sync.isIndexing, 0, 0) }
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
            guard indexing != showsProgress else { return }
            showsProgress = indexing
            if !indexing { bar?.doubleValue = 0 }
            let apply = { [self] in
                width?.animator().constant = indexing ? Self.progressWidth : Self.iconWidth
                icon?.animator().alphaValue = indexing ? 0 : 1
                progress?.animator().alphaValue = indexing ? 1 : 0
                icon?.window?.layoutIfNeeded()
            }
            guard animated else {
                width?.constant = indexing ? Self.progressWidth : Self.iconWidth
                icon?.alphaValue = indexing ? 0 : 1
                progress?.alphaValue = indexing ? 1 : 0
                return
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                ctx.allowsImplicitAnimation = true
                apply()
            }
        }
    }
}
