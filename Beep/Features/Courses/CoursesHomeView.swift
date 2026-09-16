import SwiftData
import SwiftUI

/// Home: status header + grouped course list. Sidebar on regular width.
struct CoursesHomeView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Int?

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                CoursesListView(selection: $selection)
            } detail: {
                if let selection {
                    CourseDetailView(courseID: selection)
                } else {
                    ContentUnavailableView("Pick a course", systemImage: "graduationcap", description: Text("Its material, announcements and files show up here."))
                }
            }
        } else {
            NavigationStack {
                CoursesListView(selection: $selection)
                    .navigationDestination(for: Int.self) { CourseDetailView(courseID: $0) }
            }
        }
    }
}

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

struct CoursesListView: View {
    @Binding var selection: Int?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Query(sort: \Course.title) private var courses: [Course]
    @Query(filter: #Predicate<WebeepNotification> { !$0.read }) private var unread: [WebeepNotification]
    @State private var query = ""
    @State private var yearFilter: YearFilter = .all
    @State private var showHidden = false
    @State private var onlyNew = false
    @State private var expandedYears: Set<String> = []
    @State private var showSettings = false
    @State private var showNotifications = false

    private var visible: [Course] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return courses.filter { c in
            if c.isHidden && !showHidden { return false }
            if onlyNew && c.newFilesCount == 0 { return false }
            switch yearFilter {
            case .all: break
            case .current: if c.isAcademicYear && !c.isCurrentYear { return false }
            case .past: if !c.isAcademicYear || c.isCurrentYear { return false }
            }
            guard !q.isEmpty else { return true }
            return c.title.lowercased().contains(q) || (c.code?.contains(q) ?? false) || (c.professors?.lowercased().contains(q) ?? false)
        }
    }

    private var favourites: [Course] { visible.filter(\.isFavourite) }
    private var current: [Course] { visible.filter { $0.isCurrentYear } }
    private var general: [Course] { visible.filter { !$0.isAcademicYear } }
    private var pastByYear: [(year: String, courses: [Course])] {
        let past = visible.filter { $0.isAcademicYear && !$0.isCurrentYear }
        return Dictionary(grouping: past, by: \.categoryName)
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }
    private var totalNew: Int { courses.reduce(0) { $0 + $1.newFilesCount } }

    var body: some View {
        List(selection: sizeClass == .regular ? $selection : nil) {
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
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            }

            if !favourites.isEmpty {
                Section("Favourites") { rows(favourites) }
            }
            if !current.isEmpty {
                Section("Current year") { rows(current) }
            }
            if !general.isEmpty {
                Section("Programme & general") { rows(general) }
            }
            ForEach(pastByYear, id: \.year) { group in
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Courses")
        .searchable(text: $query, prompt: "Course, code or professor")
        .searchToolbarBehavior(.minimize)
        .refreshable { await syncNow() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Years", selection: $yearFilter) {
                        ForEach(YearFilter.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Show hidden courses", systemImage: "eye.slash", isOn: $showHidden)
                    Toggle("Only with new files", systemImage: "sparkles", isOn: $onlyNew)
                } label: {
                    Label("Filter", systemImage: yearFilter == .all && !showHidden && !onlyNew ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .topBarTrailing) {
                Button("Notifications", systemImage: "bell") { showNotifications = true }
                    .badge(unread.count)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") { showSettings = true }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showNotifications) { NotificationsView() }
    }

    @ViewBuilder
    private func rows(_ list: [Course]) -> some View {
        ForEach(list) { course in
            CourseRow(course: course)
                .tag(course.id)
                .modifier(RowLink(id: course.id, isSplit: sizeClass == .regular))
                .contextMenu { CourseContextMenu(course: course) }
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
    @Environment(\.horizontalSizeClass) private var sizeClass
    let newCount: Int
    @Binding var onlyNew: Bool

    var body: some View {
        let layout = sizeClass == .compact ? AnyLayout(HStackLayout(spacing: Theme.Spacing.s)) : AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
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
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .sensoryFeedback(.selection, trigger: onlyNew)
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
        case .indexing(let done, let total): return "\(done)/\(total)"
        case .failed: return String(localized: "Failed")
        case .idle:
            if let at = sync.lastSyncAt { return at.formatted(.relative(presentation: .named)) }
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
    @Environment(\.openURL) private var openURL

    var body: some View {
        Toggle(isOn: $course.isFavourite) { Label("Favourite", systemImage: "star") }
        Toggle(isOn: $course.syncEnabled) { Label("Auto-download new files", systemImage: "arrow.down.circle") }
        Toggle(isOn: $course.isHidden) { Label("Hidden", systemImage: "eye.slash") }
        Divider()
        Button {
            openURL(WeBeep.host.appending(path: "course/view.php").appending(queryItems: [URLQueryItem(name: "id", value: String(course.id))]))
        } label: {
            Label("Open on WeBeep", systemImage: "safari")
        }
    }
}
