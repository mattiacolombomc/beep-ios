import SwiftData
import SwiftUI

/// Pick which courses download new files automatically. Grouped by year,
/// searchable, with bulk actions so 60 courses are manageable.
struct SyncCoursesView: View {
    @Query(sort: \Course.title) private var courses: [Course]
    /// Shared with the toolbar modifier as a reference: typing does not re-emit the toolbar.
    @State private var search = SearchText()
    @AppStorage("syncCourses.yearFilter") private var yearFilter: YearFilter = .current

    private var query: String { search.text }
    private var visible: [Course] { Self.visible(courses, query: query, years: yearFilter) }

    static func visible(_ courses: [Course], query: String, years: YearFilter) -> [Course] {
        courses.filter { c in
            if c.isHidden || c.isArchived { return false }
            switch years {
            case .all: break
            case .current: if c.isAcademicYear && !c.isCurrentYear { return false }
            case .past: if !c.isAcademicYear || c.isCurrentYear { return false }
            }
            return c.matches(query)
        }
    }

    private var groups: [(name: String, courses: [Course])] {
        Dictionary(grouping: visible, by: \.categoryName)
            .sorted { a, b in
                let ay = AcademicYear.isAcademicYear(a.key), by = AcademicYear.isAcademicYear(b.key)
                if ay != by { return ay }   // academic years first, newest first
                return a.key > b.key
            }
            .map { ($0.key, $0.value) }
    }

    private var enabledCount: Int { courses.filter(\.syncEnabled).count }

    var body: some View {
        List {
            Section {
                Picker("Years", selection: $yearFilter) {
                    ForEach(YearFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            } footer: {
                Text("\(enabledCount) courses auto-download new files. Tap a row to toggle; use the menu for bulk changes.")
            }
            ForEach(groups, id: \.name) { group in
                Section {
                    ForEach(group.courses) { course in
                        SyncCourseRow(course: course)
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        Text("\(group.courses.filter(\.syncEnabled).count)/\(group.courses.count)")
                            .monospacedDigit()
                    }
                }
            }
            if visible.isEmpty {
                ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
            }
        }
        .groupedList()
        .navigationTitle("Auto-download")
        .inlineNavigationTitle()
        #if os(macOS)
        // Not `.searchable`: on the Mac it is a toolbar item and each keystroke rebuilt the toolbar.
        .safeAreaInset(edge: .top, spacing: 0) {
            SidebarSearchField(text: $search.text, prompt: String(localized: "Course, code or professor"))
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
        }
        #else
        .searchable(text: $search.text, prompt: "Course, code or professor")
        #endif
        .modifier(SyncCoursesToolbar(search: search))
    }
}

/// Bulk actions. Reads the courses and the search text only when an action runs, so neither
/// typing nor toggling a row re-emits the toolbar.
private struct SyncCoursesToolbar: ViewModifier {
    let search: SearchText
    @Query(sort: \Course.title) private var courses: [Course]
    @AppStorage("syncCourses.yearFilter") private var yearFilter: YearFilter = .current

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .trailingBar) {
                Menu {
                    Button("Enable all shown", systemImage: "checkmark.circle") { set(true, shown()) }
                    Button("Disable all shown", systemImage: "circle") { set(false, shown()) }
                    Divider()
                    Button("Only current year", systemImage: "calendar") {
                        for c in courses { c.syncEnabled = c.isCurrentYear && !c.isArchived && !c.isHidden }
                    }
                    Button("Disable everything", systemImage: "xmark.circle", role: .destructive) { set(false, courses) }
                } label: {
                    Label("Bulk actions", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func shown() -> [Course] { SyncCoursesView.visible(courses, query: search.text, years: yearFilter) }

    private func set(_ value: Bool, _ list: [Course]) {
        for c in list { c.syncEnabled = value }
    }
}

private struct SyncCourseRow: View {
    @Bindable var course: Course

    var body: some View {
        Button {
            course.syncEnabled.toggle()
        } label: {
            HStack(spacing: Theme.Spacing.m - 4) {
                CourseTile(monogram: course.monogram, color: course.color, size: 40)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(course.title).font(.body).lineLimit(2).truncationMode(.middle)
                    Text([course.code, course.professors].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: course.syncEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(course.syncEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: course.syncEnabled)
        .accessibilityValue(course.syncEnabled ? "On" : "Off")
    }
}
