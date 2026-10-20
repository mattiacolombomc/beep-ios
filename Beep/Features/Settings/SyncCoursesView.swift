import SwiftData
import SwiftUI

/// Pick which courses download new files automatically. Grouped by year, searchable, with the
/// same year and period filters as the home list, and bulk actions so 60 courses are manageable.
struct SyncCoursesView: View {
    /// The parent's courses when it has them (Settings), else this view's own query (onboarding):
    /// in the Mac Settings window a `@Query` inside a pushed view came back empty.
    private let injected: [Course]?
    @Query(sort: \Course.title) private var queried: [Course]
    /// Shared with the toolbar modifier as a reference: typing does not re-emit the toolbar.
    @State private var search = SearchText()
    @AppStorage("syncCourses.yearFilter") private var yearFilter: YearFilter = .current
    @AppStorage("syncCourses.semesterFilter") private var semesterFilter: SemesterFilter = .all
    @Environment(SyncEngine.self) private var sync

    init(courses: [Course]? = nil) {
        injected = courses
    }

    private var courses: [Course] { injected ?? queried }
    private var visible: [Course] { Self.visible(courses, query: search.text, years: yearFilter, semester: semesterFilter) }

    static func visible(_ courses: [Course], query: String, years: YearFilter, semester: SemesterFilter = .all) -> [Course] {
        courses.filter { !$0.isHidden && !$0.isArchived && $0.passes(years: years, semester: semester) && $0.matches(query) }
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

    var body: some View {
        List {
            Section {
                HStack(spacing: Theme.Spacing.m) {
                    Picker("Years", selection: $yearFilter) {
                        ForEach(YearFilter.allCases) { Text($0.label).tag($0) }
                        ForEach(sync.academicYears, id: \.self) { year in
                            Text(YearFilter.year(year).label).tag(YearFilter.year(year))
                        }
                    }
                    Picker("Period", selection: $semesterFilter) {
                        ForEach(SemesterFilter.allCases) { Text($0.label).tag($0) }
                    }
                    Spacer(minLength: 0)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onAppear { sync.refreshYears() }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: Theme.Spacing.m, bottom: Theme.Spacing.xs, trailing: Theme.Spacing.m))
            .listSectionSeparator(.hidden)

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
            if courses.isEmpty {
                ContentUnavailableView("No courses yet", systemImage: "graduationcap")
                    .listRowBackground(Color.clear)
            } else if visible.isEmpty {
                ContentUnavailableView("No course matches", systemImage: "line.3.horizontal.decrease",
                                       description: Text("Change the year or period, or the search."))
                    .listRowBackground(Color.clear)
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
        .modifier(SyncCoursesToolbar(search: search, courses: courses))
    }
}

/// Bulk actions. Reads the courses and the search text only when an action runs, so neither
/// typing nor toggling a row re-emits the toolbar.
private struct SyncCoursesToolbar: ViewModifier {
    let search: SearchText
    let courses: [Course]
    @AppStorage("syncCourses.yearFilter") private var yearFilter: YearFilter = .current
    @AppStorage("syncCourses.semesterFilter") private var semesterFilter: SemesterFilter = .all

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

    private func shown() -> [Course] { SyncCoursesView.visible(courses, query: search.text, years: yearFilter, semester: semesterFilter) }

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
                    Text([course.semester.shortLabelText, course.code, course.professors].compactMap { $0 }.joined(separator: " · "))
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

private extension Semester {
    /// "1st sem" as plain text for the row's detail line.
    var shortLabelText: String? {
        switch self {
        case .unknown: nil
        case .first: String(localized: "1st sem")
        case .second: String(localized: "2nd sem")
        case .annual: String(localized: "Annual")
        }
    }
}
