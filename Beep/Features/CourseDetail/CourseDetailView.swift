import SwiftData
import SwiftUI

enum FileTypeScope: String, CaseIterable, Identifiable {
    case all, pdf, slides, video, archive, other
    var id: Self { self }
    var label: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .pdf: "PDF"
        case .slides: "Slides & docs"
        case .video: "Video"
        case .archive: "Archives"
        case .other: "Other"
        }
    }
    func matches(_ ext: String) -> Bool {
        switch self {
        case .all: true
        case .pdf: ext == "pdf"
        case .slides: ["ppt", "pptx", "key", "doc", "docx", "odt", "odp", "txt", "md", "rtf", "xls", "xlsx"].contains(ext)
        case .video: ["mp4", "mov", "m4v", "mkv", "avi", "webm", "mp3", "m4a"].contains(ext)
        case .archive: ["zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext)
        case .other: !["pdf", "ppt", "pptx", "key", "doc", "docx", "odt", "odp", "txt", "md", "rtf", "xls", "xlsx", "mp4", "mov", "m4v", "mkv", "avi", "webm", "mp3", "m4a", "zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext)
        }
    }
}

enum FileSort: String, CaseIterable, Identifiable {
    case position, newest, name
    var id: Self { self }
    var label: LocalizedStringKey {
        switch self {
        case .position: "Course order"
        case .newest: "Newest first"
        case .name: "Name"
        }
    }
}

struct CourseDetailView: View {
    let courseID: Int
    @Query private var courses: [Course]

    init(courseID: Int) {
        self.courseID = courseID
        _courses = Query(filter: #Predicate<Course> { $0.id == courseID })
    }

    var body: some View {
        if let course = courses.first {
            CourseContentView(course: course)
        } else {
            ContentUnavailableView("Course not found", systemImage: "questionmark.folder")
        }
    }
}

private struct CourseContentView: View {
    @Bindable var course: Course
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    #if os(macOS)
    /// Native toolbar field (see `ToolbarSearch`): `.searchable` rebuilt the toolbar per keystroke.
    @State private var search = SearchText()
    private var query: String { search.text }
    #else
    @State private var query = ""
    #endif
    @State private var scope: FileTypeScope = .all
    /// Sort, "only new" and the rename dialog live in a reference type shared with the toolbar
    /// modifier: the toolbar's inputs stay identical while the user types or the list updates.
    @State private var options = CourseViewOptions()
    @State private var lastSeenAtOpen: Date?
    @State private var selection = FileSelection()

    private var sort: FileSort { options.sort }
    private var onlyNew: Bool { options.onlyNew }
    private var isFiltering: Bool { !query.isEmpty || scope != .all || onlyNew || sort != .position }

    /// Files the selection bar can act on: the filtered list, or every file of the course.
    /// Sorting every file reads each one's module and section: only done while selecting.
    private func selectableFiles(filtered: [FileItem]) -> [FileItem] {
        guard selection.isActive else { return [] }
        return isFiltering
            ? filtered
            : course.files.sorted { a, b in
                let sa = a.module?.section?.position ?? 0, sb = b.module?.section?.position ?? 0
                if sa != sb { return sa < sb }
                let ma = a.module?.position ?? 0, mb = b.module?.position ?? 0
                if ma != mb { return ma < mb }
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            }
    }

    var body: some View {
        // Filtered once per render and shared by the list and the selection bar.
        let filtered = isFiltering
            ? FilteredFilesSection.files(of: course, query: query, scope: scope, sort: sort, onlyNew: onlyNew, lastSeen: lastSeenAtOpen)
            : []
        List {
            if !isFiltering {
                Section {
                    CourseHeader(course: course, lastSeen: lastSeenAtOpen)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)
            }

            if isFiltering {
                FilteredFilesSection(files: filtered, query: query, lastSeen: lastSeenAtOpen)
            } else if course.sections.isEmpty {
                ContentUnavailableView {
                    Label(course.lastIndexedAt == nil ? "Not loaded yet" : "Empty course", systemImage: "tray")
                } description: {
                    Text(course.lastIndexedAt == nil ? "Pull to refresh to load the course material." : "This course has no content on WeBeep yet.")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(course.sections.sorted { $0.position < $1.position }) { section in
                    if !section.modules.isEmpty {
                        Section {
                            ForEach(section.modules.sorted { $0.position < $1.position }) { module in
                                ModuleRow(module: module, course: course, lastSeen: lastSeenAtOpen)
                            }
                        } header: {
                            Text(section.name)
                        }
                    }
                }
            }
        }
        .groupedList()
        // Typing swaps the rows: no animated diff of hundreds of insertions per keystroke.
        .animation(nil, value: query)
        .selectionBar(selection, candidates: selectableFiles(filtered: filtered))
        .animation(.snappy, value: selection.isActive)
        .environment(selection)
        .sectionTitle(verbatim: course.title)
        .inlineNavigationTitle()
        #if os(macOS)
        .modifier(ToolbarSearch(search: search, prompt: "Search in this course"))
        .safeAreaInset(edge: .top, spacing: 0) {
            if !query.isEmpty {
                Picker("Type", selection: $scope) {
                    ForEach(FileTypeScope.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, Theme.Spacing.s)
                .background(.bar)
            }
        }
        #else
        .searchable(text: $query, prompt: "Search in this course")
        .searchScopes($scope, activation: .onSearchPresentation) {
            ForEach(FileTypeScope.allCases) { Text($0.label).tag($0) }
        }
        #endif
        .refreshable { await refresh() }
        #if os(macOS)
        .modifier(CourseToolbar(options: options, selection: selection))
        #else
        .modifier(CourseToolbar(course: course, options: options, selection: selection))
        #endif
        #if DEBUG || BENCH
        .task {
            guard TypingBenchmark.isEnabled else { return }
            #if os(macOS)
            await TypingBenchmark.run { search.text = $0 }
            #else
            await TypingBenchmark.run { query = $0 }
            #endif
        }
        #endif
        .renameFolderDialog(course: $options.renameTarget)
        // The Mac keeps this screen when another course opens (no rebuild of its toolbar): start
        // each course with a clean search, sort and selection.
        .onChange(of: course.id) { _, _ in
            selection.end()
            #if os(macOS)
            search.text = ""
            #else
            query = ""
            #endif
            scope = .all
            options.sort = .position
            options.onlyNew = false
        }
        .onDisappear { selection.end() }
        .task(id: course.id) {
            options.course = course
            // Remember what "new" meant when the screen opened, then mark everything seen.
            lastSeenAtOpen = course.lastSeenAt
            // Writing the course makes every list re-run its query. With no new files, moving
            // `lastSeenAt` forward changes nothing (no file lies between the two dates): skip it.
            if course.lastSeenAt == nil || course.newFilesCount > 0 {
                course.lastSeenAt = .now
                course.newFilesCount = 0
            }
            if course.lastIndexedAt == nil { await refresh() }
        }
    }

    private func refresh() async {
        guard let client = session.client else { return }
        _ = await sync.sync(course: course, client: client)
    }
}

private struct CourseHeader: View {
    @Bindable var course: Course
    let lastSeen: Date?
    @Environment(SyncEngine.self) private var sync
    private var missing: Int { course.files.reduce(0) { $0 + (($1.isDownloaded && !$1.hasUpdate) ? 0 : 1) } }

    private var totalSize: Int { course.files.reduce(0) { $0 + $1.filesize } }
    private var newCount: Int { course.files.reduce(0) { $0 + ($1.isNew(relativeTo: lastSeen) ? 1 : 0) } }
    private var downloaded: Int { course.files.reduce(0) { $0 + ($1.isDownloaded ? 1 : 0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.m - 4) {
                CourseTile(monogram: course.monogram, color: course.color, size: 56)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(course.title)
                        .font(.title2.weight(.bold))
                        .lineLimit(3)
                        .padding(.bottom, 2)
                    // Same year tag, code and professors as the course rows in the sidebar.
                    CourseMetaLine(course: course)
                    if !course.isAcademicYear {
                        Text(course.categoryName).font(.subheadline).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.Spacing.l) {
                Stat(value: "\(course.files.count)", label: "files")
                Stat(value: "\(newCount)", label: "new", highlighted: newCount > 0)
                Stat(value: totalSize == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file), label: "total")
                Stat(value: "\(downloaded)", label: "offline")
                Spacer(minLength: 0)
            }
            HStack(spacing: Theme.Spacing.s) {
                Button {
                    sync.downloadAll(of: course)
                } label: {
                    Label(missing == 0 ? "All files offline" : "Download all (\(missing))", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(missing == 0)
                Toggle(isOn: $course.syncEnabled) {
                    Label("Auto", systemImage: "arrow.triangle.2.circlepath")
                }
                .toggleStyle(.button)
                .buttonBorderShape(.capsule)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s)
    }

    private struct Stat: View {
        let value: String
        let label: LocalizedStringKey
        var highlighted = false
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(highlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText())
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Flat, filtered view of the course's files with section › folder breadcrumbs.
struct FilteredFilesSection: View {
    let files: [FileItem]
    let query: String
    let lastSeen: Date?

    static func files(of course: Course, query: String, scope: FileTypeScope, sort: FileSort, onlyNew: Bool, lastSeen: Date?) -> [FileItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var list = course.files.filter { f in
            guard scope.matches(f.fileExtension) else { return false }
            if onlyNew && !f.isNew(relativeTo: lastSeen) { return false }
            guard !q.isEmpty else { return true }
            return f.filename.lowercased().contains(q)
                || f.filepath.lowercased().contains(q)
                || (f.module?.name.lowercased().contains(q) ?? false)
        }
        switch sort {
        case .position:
            list.sort { a, b in
                let sa = a.module?.section?.position ?? 0, sb = b.module?.section?.position ?? 0
                if sa != sb { return sa < sb }
                let ma = a.module?.position ?? 0, mb = b.module?.position ?? 0
                if ma != mb { return ma < mb }
                return a.filename.localizedStandardCompare(b.filename) == .orderedAscending
            }
        case .newest: list.sort { $0.timemodified > $1.timemodified }
        case .name: list.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        }
        return list
    }

    var body: some View {
        let result = files
        if result.isEmpty {
            ContentUnavailableView.search(text: query)
                .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(result) { file in
                    FileRow(file: file, isNew: file.isNew(relativeTo: lastSeen), showsLocation: true)
                }
            } header: {
                Text("\(result.count) files")
            }
        }
    }
}

/// View options of one course screen, shared with its toolbar.
@Observable
final class CourseViewOptions {
    var sort: FileSort = .position
    var onlyNew = false
    var renameTarget: Course?
    /// The course on screen, read by the Mac "…" menu when it opens.
    var course: Course?

    var isCustomized: Bool { sort != .position || onlyNew }
}

/// The course screen's "…" menu. Its inputs are references (course, options, selection), so
/// typing in the search field or a list update does not re-emit it and AppKit keeps the toolbar.
private struct CourseToolbar: ViewModifier {
    #if !os(macOS)
    // Not an input on the Mac: a new course would re-emit the toolbar (the menu reads
    // `options.course` when it opens).
    let course: Course
    #endif
    let options: CourseViewOptions
    let selection: FileSelection
    @ActiveSection private var isActive

    @ViewBuilder func body(content: Content) -> some View {
        toolbar(content)
    }

    #if os(macOS)
    @Environment(FileOpener.self) private var opener
    private func toolbar(_ content: Content) -> some View {
        content.toolbar {
            if isActive {
                ToolbarItem(placement: .trailingBar) {
                    if selection.isActive {
                        Button("Done") { selection.end() }
                    } else {
                        CourseMenuButton(options: options, selection: selection, opener: opener)
                            .frame(width: 28, height: 22)
                            .help("More")
                    }
                }
            }
        }
    }
    #else
    private func toolbar(_ content: Content) -> some View {
        @Bindable var options = options
        // Read here on purpose: the menu is rebuilt (and shows the right checkmarks) when the
        // sort or the "only new" filter changes, never while typing.
        let changed = options.sort != .position || options.onlyNew
        return content.toolbar {
            if isActive {
            ToolbarItem(placement: .trailingBar) {
                if selection.isActive {
                    Button("Done") { selection.end() }
                } else {
                    Menu {
                        Button("Select", systemImage: "checkmark.circle") { selection.begin() }
                            .disabled(course.files.isEmpty)
                        Divider()
                        Picker("Sort", selection: $options.sort) {
                            ForEach(FileSort.allCases) { Text($0.label).tag($0) }
                        }
                        Toggle("Only new files", systemImage: "sparkles", isOn: $options.onlyNew)
                        if changed {
                            Button("Reset view", systemImage: "arrow.uturn.backward") {
                                options.sort = .position
                                options.onlyNew = false
                            }
                        }
                        Divider()
                        CourseContextMenu(course: course, onRename: { options.renameTarget = course })
                    } label: {
                        Label("More", systemImage: changed ? "ellipsis.circle.fill" : "ellipsis.circle")
                    }
                }
            }
            }
        }
    }
    #endif
}
