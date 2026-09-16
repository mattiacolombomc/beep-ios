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
    @State private var query = ""
    @State private var scope: FileTypeScope = .all
    @State private var sort: FileSort = .position
    @State private var onlyNew = false
    @State private var lastSeenAtOpen: Date?

    private var isFiltering: Bool { !query.isEmpty || scope != .all || onlyNew || sort != .position }

    var body: some View {
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
                FilteredFilesSection(course: course, query: query, scope: scope, sort: sort, onlyNew: onlyNew, lastSeen: lastSeenAtOpen)
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
        .listStyle(.insetGrouped)
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search in this course")
        .searchScopes($scope, activation: .onSearchPresentation) {
            ForEach(FileTypeScope.allCases) { Text($0.label).tag($0) }
        }
        .refreshable { await refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(FileSort.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Only new files", systemImage: "sparkles", isOn: $onlyNew)
                    Divider()
                    CourseContextMenu(course: course)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .task(id: course.id) {
            // Remember what "new" meant when the screen opened, then mark everything seen.
            lastSeenAtOpen = course.lastSeenAt
            course.lastSeenAt = .now
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
                    if let code = course.code {
                        Text(code)
                            .font(.caption.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(.secondary)
                    }
                    if let profs = course.professors {
                        Text(profs).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(course.categoryName).font(.subheadline).foregroundStyle(.tertiary)
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
private struct FilteredFilesSection: View {
    let course: Course
    let query: String
    let scope: FileTypeScope
    let sort: FileSort
    let onlyNew: Bool
    let lastSeen: Date?

    private var files: [FileItem] {
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
