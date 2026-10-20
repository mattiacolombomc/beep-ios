import SwiftData
import SwiftUI

#if os(iOS)
/// Home: status header + grouped course list. Sidebar on regular width.
struct CoursesHomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppRouter.self) private var router
    @State private var selection: Int?
    @State private var path = NavigationPath()

    var body: some View {
        content
            .onChange(of: router.pending, initial: true) { _, dest in
                guard case .course(let id) = dest else { return }
                if sizeClass == .regular { selection = id } else { path = NavigationPath([id]) }
                router.pending = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                CoursesListView(selection: $selection, isSplit: true)
                    .navigationSplitViewColumnWidth(min: 340, ideal: 400, max: 520)
            } detail: {
                if let selection {
                    NavigationStack {
                        CourseDetailView(courseID: selection)
                            .courseRoutes()
                    }
                } else {
                    ContentUnavailableView("Pick a course", systemImage: "graduationcap", description: Text("Its material, announcements and files show up here."))
                }
            }
        } else {
            NavigationStack(path: $path) {
                CoursesListView(selection: $selection, isSplit: false)
                    .navigationDestination(for: Int.self) { CourseDetailView(courseID: $0) }
                    .courseRoutes()
            }
        }
    }
}
#endif

enum YearFilter: String, CaseIterable, Identifiable {
    case all, current, past
    var id: Self { self }
    var label: LocalizedStringKey {
        switch self {
        case .all: "All years"
        case .current: "Current year"
        case .past: "Past years"
        }
    }
}

/// Teaching period filter. "Current semester" is the one under way now (`AcademicYear.currentSemester`)
/// in the current year; annual courses pass every semester filter, courses whose period is still
/// unknown pass none, courses outside an academic year are left alone.
enum SemesterFilter: String, CaseIterable, Identifiable {
    case all, current, first, second
    var id: Self { self }
    var label: LocalizedStringKey {
        switch self {
        case .all: "All periods"
        case .current: "Current semester"
        case .first: "1st semester"
        case .second: "2nd semester"
        }
    }
    /// The semester kept by this filter, as of now.
    var semester: Semester? {
        switch self {
        case .all: nil
        case .current: AcademicYear.currentSemester()
        case .first: .first
        case .second: .second
        }
    }
}

struct CoursesListView: View {
    @Binding var selection: Int?
    /// True when hosted as the sidebar of a split view (rows select instead of pushing).
    /// Read from the parent: the sidebar column itself reports a compact size class.
    let isSplit: Bool
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(AppRouter.self) private var router
    @Query(sort: \Course.title) private var courses: [Course]
    @State private var query = ""
    @AppStorage("home.yearFilter") private var yearFilter: YearFilter = .all
    @AppStorage("home.semesterFilter") private var semesterFilter: SemesterFilter = .all
    @AppStorage("home.showHidden") private var showHidden = false
    @AppStorage("home.showArchived") private var showArchived = false
    @AppStorage("home.onlyNew") private var onlyNew = false
    @AppStorage("home.onlyAutoDownload") private var onlyAutoDownload = false
    @State private var expandedYears: Set<String> = []
    @State private var archiveTarget: Course?
    @State private var renameTarget: Course?
    @State private var unenrolTarget: Course?

    private var visible: [Course] {
        return courses.filter { c in
            if c.isHidden && !showHidden { return false }
            if c.isArchived && !showArchived { return false }
            if onlyNew && c.newFilesCount == 0 { return false }
            if onlyAutoDownload && !c.syncEnabled { return false }
            switch yearFilter {
            case .all: break
            case .current: if c.isAcademicYear && !c.isCurrentYear { return false }
            case .past: if !c.isAcademicYear || c.isCurrentYear { return false }
            }
            if let semester = semesterFilter.semester, c.isAcademicYear {
                if semesterFilter == .current && !c.isCurrentYear { return false }
                if !c.semester.runs(in: semester) { return false }
            }
            return c.matches(query)
        }
    }

    /// Every list section in one pass over `visible`: the body recomputed the filter once per
    /// section (six passes), and it runs again on every sync save.
    private struct Groups {
        var isEmpty = true
        var favourites: [Course] = [], current: [Course] = [], general: [Course] = [], archived: [Course] = []
        var pastByYear: [(year: String, courses: [Course])] = []
    }
    private var groups: Groups {
        var g = Groups()
        var past: [String: [Course]] = [:]
        let currentYear = AcademicYear.currentStartYear()
        for c in visible {
            g.isEmpty = false
            if c.isArchived { g.archived.append(c); continue }
            if c.isFavourite { g.favourites.append(c) }
            let year = AcademicYear.startYear(c.categoryName)
            if year == nil { g.general.append(c) }
            else if year == currentYear { g.current.append(c) }
            else { past[c.categoryName, default: []].append(c) }
        }
        g.pastByYear = past.sorted { $0.key > $1.key }.map { ($0.key, $0.value) }
        return g
    }
    private var totalNew: Int { courses.reduce(0) { $0 + $1.newFilesCount } }

    var body: some View {
        let g = groups
        List(selection: isSplit ? $selection : nil) {
            if query.isEmpty {
                Section {
                    StatusHeader(newCount: totalNew, onlyNew: $onlyNew)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)
            }

            if courses.isEmpty {
                ContentUnavailableView {
                    Label("No courses yet", systemImage: "graduationcap")
                } description: {
                    Text("Pull to refresh or tap Sync to load your WeBeep courses.")
                }
                .listRowBackground(Color.clear)
            } else if g.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }

            if !g.favourites.isEmpty {
                Section("Favourites") { rows(g.favourites) }
            }
            if !g.current.isEmpty {
                Section("Current year") { rows(g.current) }
            }
            if !g.general.isEmpty {
                Section("Programme & general") { rows(g.general) }
            }
            ForEach(g.pastByYear, id: \.year) { group in
                Section {
                    DisclosureGroup(isExpanded: binding(for: group.year)) {
                        rows(group.courses)
                    } label: {
                        HStack {
                            Text(group.year).font(.headline)
                            Spacer()
                            Text("\(group.courses.count)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .animation(.spring(duration: 0.32, bounce: 0.18), value: expandedYears)
                }
            }
            if !g.archived.isEmpty {
                Section {
                    DisclosureGroup(isExpanded: binding(for: "archived")) {
                        rows(g.archived)
                    } label: {
                        HStack {
                            Label("Archived", systemImage: "archivebox").font(.headline)
                            Spacer()
                            Text("\(g.archived.count)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .groupedList()
        .sectionTitle("Courses")
        .largeNavigationTitle()
        #if os(macOS)
        // Not `.searchable`: on the Mac it is a toolbar item, and each keystroke rebuilt the toolbar.
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarSearchField(text: $query, prompt: String(localized: "Course, code or professor"))
                .padding(.horizontal, Theme.Spacing.s + 2)
                .padding(.vertical, Theme.Spacing.s)
        }
        #else
        .searchable(text: $query, prompt: "Course, code or professor")
        #endif
        .minimizedSearchToolbar()
        .refreshable { await syncNow() }
        // The toolbar lives in its own modifier with no inputs: typing in the search field, a sync
        // refreshing `courses`, or any other change of this view does not re-emit the toolbar, so
        // AppKit does not rebuild it (that rebuild made the bar flash and closed open menus).
        .modifier(CoursesListToolbar())
        #if DEBUG || BENCH
        .task { if TypingBenchmark.isEnabled && ProcessInfo.processInfo.arguments.contains("-sidebar") { await TypingBenchmark.run { query = $0 } } }
        #endif
        .archiveDialog(course: $archiveTarget)
        .renameFolderDialog(course: $renameTarget)
        .unenrolDialog(course: $unenrolTarget)
    }


    @ViewBuilder
    private func rows(_ list: [Course]) -> some View {
        ForEach(list) { course in
            CourseRow(course: course)
                .tag(course.id)
                .modifier(RowLink(id: course.id, isSplit: isSplit))
                .contextMenu { CourseContextMenu(course: course, onArchive: { archiveTarget = course }, onRename: { renameTarget = course }, onUnenrol: { unenrolTarget = course }) }
                .swipeActions(edge: .trailing) {
                    if course.isArchived {
                        Button { course.isArchived = false } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
                    } else {
                        Button { archiveTarget = course } label: { Label("Archive", systemImage: "archivebox") }
                    }
                    Button {
                        course.syncEnabled.toggle()
                    } label: {
                        Label(course.syncEnabled ? "Stop auto-download" : "Auto-download", systemImage: course.syncEnabled ? "arrow.down.circle.dotted" : "arrow.down.circle")
                    }
                    .tint(.accentColor)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        course.isFavourite.toggle()
                    } label: {
                        Label(course.isFavourite ? "Unfavourite" : "Favourite", systemImage: course.isFavourite ? "star.slash" : "star")
                    }
                    .tint(.yellow)
                }
        }
    }

    private func binding(for year: String) -> Binding<Bool> {
        Binding(get: { expandedYears.contains(year) },
                set: { if $0 { expandedYears.insert(year) } else { expandedYears.remove(year) } })
    }

    private func syncNow() async {
        guard let client = session.client, let user = session.user else { return }
        let report = await sync.syncAll(client: client, userID: user.id)
        if report.errors.contains(where: { $0.contains("invalidToken") }) { session.signOut() }
    }
}

/// In a split view rows are selected; in a stack they push.
private struct RowLink: ViewModifier {
    let id: Int
    let isSplit: Bool
    func body(content: Content) -> some View {
        if isSplit {
            content
        } else {
            NavigationLink(value: id) { content }
        }
    }
}

private struct StatusHeader: View {
    @Environment(SyncEngine.self) private var sync
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #else
    /// On the Mac the header sits in the sidebar: keep it to two tiles.
    private let isCompact = true
    #endif
    let newCount: Int
    @Binding var onlyNew: Bool

    var body: some View {
        let layout = isCompact ? AnyLayout(HStackLayout(spacing: Theme.Spacing.s)) : AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
        layout {
            Button {
                onlyNew.toggle()
            } label: {
                StatusTile(symbol: "sparkles", title: "New files", value: "\(newCount)",
                           detail: newCount == 0 ? "You're up to date" : "Since your last visit",
                           tint: .accentColor, isProminent: onlyNew)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(newCount) new files")

            StatusTile(symbol: syncSymbol, title: "Sync", value: syncValue, detail: syncDetail, tint: .secondary)
            if !isCompact {
                StatusTile(symbol: "arrow.down.circle", title: "Downloads", value: downloadValue, detail: downloadDetail, tint: .secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .sensoryFeedback(.selection, trigger: onlyNew)
    }

    private var downloadValue: String {
        let p = sync.downloads.progress
        return p.isBusy ? "\(p.completedInSession)/\(p.total)" : "\(p.completedInSession)"
    }
    private var downloadDetail: LocalizedStringKey {
        sync.downloads.progress.isBusy ? "Downloading…" : "Downloaded this session"
    }

    private var syncSymbol: String {
        switch sync.phase {
        case .idle: "checkmark.circle"
        case .indexing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.triangle"
        }
    }
    private var syncValue: String {
        switch sync.phase {
        case .indexing(let done, let total, _): return "\(done)/\(total)"
        case .failed: return String(localized: "Failed")
        case .idle:
            if let at = sync.lastSyncAt { return at.relativeLabel }
            return String(localized: "Never")
        }
    }
    private var syncDetail: LocalizedStringKey {
        switch sync.phase {
        case .indexing: "Updating courses…"
        case .failed: "Pull to retry"
        case .idle: "Last update"
        }
    }
}

struct CourseContextMenu: View {
    @Bindable var course: Course
    var onArchive: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onUnenrol: (() -> Void)? = nil
    @Environment(\.openURL) private var openURL
    @Environment(FileOpener.self) private var opener
    @Environment(SyncEngine.self) private var sync

    /// Manual period, or -1 for "whatever the catalogue says".
    private var periodChoice: Binding<Int> {
        Binding(get: { course.semesterIsManual ? course.semesterRaw : -1 },
                set: { raw in
                    if raw < 0 {
                        course.semesterIsManual = false
                        course.semesterCheckedAt = nil
                        Task { await sync.semesters.resolve(course) }
                    } else {
                        course.semesterIsManual = true
                        course.semesterRaw = raw
                    }
                })
    }

    var body: some View {
        Toggle(isOn: $course.isFavourite) { Label("Favourite", systemImage: "star") }
        Toggle(isOn: $course.syncEnabled) { Label("Auto-download new files", systemImage: "arrow.down.circle") }
        if course.isAcademicYear && course.code != nil {
            Menu {
                Picker("Period", selection: periodChoice) {
                    Text("From the catalogue").tag(-1)
                    Text("1st semester").tag(Semester.first.rawValue)
                    Text("2nd semester").tag(Semester.second.rawValue)
                    Text("Annual").tag(Semester.annual.rawValue)
                }
            } label: {
                Label("Period", systemImage: "calendar")
            }
        }
        #if os(macOS)
        if let dir = opener.directory(of: course) {
            Button { opener.reveal(dir) } label: { Label("Show in Finder", systemImage: "folder") }
        }
        #endif
        if let onRename {
            Button(action: onRename) { Label("Rename folder…", systemImage: "folder.badge.gearshape") }
        }
        if course.isArchived {
            Button { course.isArchived = false } label: { Label("Unarchive", systemImage: "tray.and.arrow.up") }
        } else if let onArchive {
            Button(action: onArchive) { Label("Archive…", systemImage: "archivebox") }
        }
        Divider()
        Button {
            openURL(WeBeep.host.appending(path: "course/view.php").appending(queryItems: [URLQueryItem(name: "id", value: String(course.id))]))
        } label: {
            Label("Open on WeBeep", systemImage: "safari")
        }
        if let onUnenrol {
            Button(role: .destructive, action: onUnenrol) { Label("Unenrol from WeBeep…", systemImage: "person.crop.circle.badge.minus") }
        }
    }
}

/// Leave a course on WeBeep (self-enrolment only), then drop it locally.
private struct UnenrolDialog: ViewModifier {
    @Binding var course: Course?
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(FileOpener.self) private var opener
    @Environment(\.modelContext) private var context
    @State private var working = false
    @State private var message: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(course.map { Text("Leave \u{201C}\($0.title)\u{201D} on WeBeep?") } ?? Text(""),
                                isPresented: Binding(get: { course != nil && !working }, set: { if !$0 { course = nil } }), titleVisibility: .visible) {
                if let c = course {
                    Button("Unenrol and keep files", role: .destructive) { Task { await run(c, deleteFiles: false) } }
                    if c.files.contains(where: \.isDownloaded) {
                        Button("Unenrol and delete files", role: .destructive) { Task { await run(c, deleteFiles: true) } }
                    }
                }
            } message: {
                Text("This is the same as “Unenrol me” on the WeBeep website. Only courses with self-enrolment allow it; you can enrol again from the catalogue.")
            }
            .overlay {
                if working {
                    ProgressView("Talking to WeBeep…").padding(Theme.Spacing.l).background(.regularMaterial, in: .rect(cornerRadius: Theme.cardRadius))
                }
            }
            .alert("Unenrolment", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(message ?? "") }
    }

    private func run(_ c: Course, deleteFiles: Bool) async {
        working = true
        defer { working = false; course = nil }
        do {
            // Demo mode (App Review, screenshots): simulate, never call WeBeep.
            if !DemoData.isEnabled { try await Unenroller.unenrol(course: c, session: session) }
            if deleteFiles { for f in c.files where f.isDownloaded { opener.removeLocal(f) } }
            context.delete(c)
            try? context.save()
            message = String(localized: "Done. You are no longer enrolled in \(c.title).")
        } catch {
            message = String(describing: error)
        }
    }
}

extension View {
    func unenrolDialog(course: Binding<Course?>) -> some View { modifier(UnenrolDialog(course: course)) }
}


/// Archive confirmation: keep or delete the downloaded files.
private struct ArchiveDialog: ViewModifier {
    @Binding var course: Course?
    @Environment(FileOpener.self) private var opener

    func body(content: Content) -> some View {
        content.confirmationDialog(
            course.map { Text("Archive \u{201C}\($0.title)\u{201D}?") } ?? Text(""),
            isPresented: Binding(get: { course != nil }, set: { if !$0 { course = nil } }),
            titleVisibility: .visible
        ) {
            if let c = course {
                let downloaded = c.files.filter(\.isDownloaded)
                let size = downloaded.reduce(0) { $0 + $1.filesize }
                Button("Archive, keep files") { archive(c, deleteFiles: false) }
                if !downloaded.isEmpty {
                    Button("Archive and delete \(downloaded.count) files (\(size.fileSizeLabel))", role: .destructive) { archive(c, deleteFiles: true) }
                }
            }
        } message: {
            Text("The course moves to the Archived group and stops auto-downloading. You can unarchive it any time.")
        }
    }

    private func archive(_ c: Course, deleteFiles: Bool) {
        c.isArchived = true
        c.syncEnabled = false
        if deleteFiles { for f in c.files where f.isDownloaded { opener.removeLocal(f) } }
        course = nil
    }
}

extension View {
    func archiveDialog(course: Binding<Course?>) -> some View { modifier(ArchiveDialog(course: course)) }
}


/// Destinations reachable from a course: forum, discussion, page.
extension View {
    func courseRoutes() -> some View {
        self
            .navigationDestination(for: CatalogRoute.self) { CatalogSearchView(initialQuery: $0.query) }
            .navigationDestination(for: ForumRoute.self) { ForumDiscussionsView(module: $0.module) }
            .navigationDestination(for: DiscussionRoute.self) { DiscussionView(route: $0) }
            .navigationDestination(for: PageRoute.self) { PageView(module: $0.module) }
    }
}


/// Rename the on-disk folder of a course (visible in the Files app).
private struct RenameFolderDialog: ViewModifier {
    @Binding var course: Course?
    @Environment(FileOpener.self) private var opener
    @State private var name = ""
    @State private var error: String?

    func body(content: Content) -> some View {
        content
            .alert("Folder name", isPresented: Binding(get: { course != nil }, set: { if !$0 { course = nil } }), presenting: course) { c in
                TextField("Folder name", text: $name)
                Button("Rename") { rename(c, to: name) }
                Button("Use course title") { rename(c, to: c.title) }
                Button("Cancel", role: .cancel) {}
            } message: { c in
                Text("Files of \u{201C}\(c.title)\u{201D} live in Files → Beep → this folder. Existing downloads are moved.")
            }
            .onChange(of: course?.id) { _, _ in
                if let c = course { name = c.folderName.isEmpty ? c.title : c.folderName }
            }
            .alert("Rename failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
    }

    private func rename(_ c: Course, to newName: String) {
        do { try opener.renameFolder(of: c, to: newName) } catch { self.error = String(describing: error) }
        course = nil
    }
}

extension View {
    func renameFolderDialog(course: Binding<Course?>) -> some View { modifier(RenameFolderDialog(course: course)) }
}

/// The course list's filters. A view of its own, reading the same `@AppStorage` keys as the list,
/// so it sits in the iOS navigation bar and in the Mac window toolbar alike.
struct CoursesFilterMenu: View {
    let findOtherCourses: () -> Void
    @Environment(SyncEngine.self) private var sync
    @AppStorage("home.yearFilter") private var yearFilter: YearFilter = .all
    @AppStorage("home.semesterFilter") private var semesterFilter: SemesterFilter = .all
    @AppStorage("home.showHidden") private var showHidden = false
    @AppStorage("home.showArchived") private var showArchived = false
    @AppStorage("home.onlyNew") private var onlyNew = false
    @AppStorage("home.onlyAutoDownload") private var onlyAutoDownload = false

    private var isFilterActive: Bool { yearFilter != .all || semesterFilter != .all || showHidden || showArchived || onlyNew || onlyAutoDownload }

    var body: some View {
        Menu {
            Picker("Years", selection: $yearFilter) {
                ForEach(YearFilter.allCases) { Text($0.label).tag($0) }
            }
            Picker("Period", selection: $semesterFilter) {
                ForEach(SemesterFilter.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Only with new files", systemImage: "sparkles", isOn: $onlyNew)
            Toggle("Only auto-download", systemImage: "arrow.down.circle", isOn: $onlyAutoDownload)
            Divider()
            Toggle("Show archived", systemImage: "archivebox", isOn: $showArchived)
            Toggle("Show hidden on WeBeep", systemImage: "eye.slash", isOn: $showHidden)
            Divider()
            Button { sync.semesters.resolveDue(force: true) } label: { Label("Refresh periods from the catalogue", systemImage: "calendar.badge.clock") }
                .disabled(sync.semesters.isRunning)
            Button(action: findOtherCourses) { Label("Find other courses…", systemImage: "books.vertical") }
        } label: {
            Label("Filter", systemImage: isFilterActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
        }
    }
}

#if os(macOS)
/// The Mac window toolbar holds the filters, notifications and settings (`MainToolbar`); the list
/// keeps the catalogue destination its "Find other courses…" item opens.
private struct CoursesListToolbar: ViewModifier {
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        @Bindable var router = router
        content.navigationDestination(isPresented: $router.showCatalog) { CatalogSearchView(initialQuery: "") }
    }
}
#else
/// Filters, notifications and settings of the course list. It reads its own state (the unread
/// count, the filters in `CoursesFilterMenu`) so the list's frequent re-renders never reach it.
private struct CoursesListToolbar: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<WebeepNotification> { !$0.read }) private var unread: [WebeepNotification]
    @State private var showCatalog = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .trailingBar) {
                    CoursesFilterMenu { showCatalog = true }
                }
                ToolbarSpacer(.fixed)
                ToolbarItem(placement: .trailingBar) {
                    Button("Notifications", systemImage: "bell") { router.showNotifications = true }
                        .badge(unread.count)
                }
                ToolbarItem(placement: .trailingBar) {
                    Button("Settings", systemImage: "gearshape") { router.showSettings = true }
                }
            }
            .navigationDestination(isPresented: $showCatalog) { CatalogSearchView(initialQuery: "") }
    }
}
#endif
