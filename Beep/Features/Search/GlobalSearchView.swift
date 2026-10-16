import SwiftData
import SwiftUI

/// Search files across every course, plus courses by name.
struct GlobalSearchView: View {
    @Query(sort: \Course.title) private var courses: [Course]
    @Environment(\.modelContext) private var context
    #if os(macOS)
    /// Native toolbar field (see `ToolbarSearch`): `.searchable` rebuilt the toolbar per keystroke.
    @State private var search = SearchText()
    private var query: String { search.text }
    #else
    @State private var query = ""
    #endif
    @State private var scope: FileTypeScope = .all
    @State private var results: [FileItem] = []
    @State private var selection = FileSelection()
    @FocusState private var searchFocused: Bool
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty {
                    let matchedCourses = courses.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.code?.contains(query) ?? false) || ($0.professors?.localizedCaseInsensitiveContains(query) ?? false) }
                    if !matchedCourses.isEmpty {
                        Section("Courses") {
                            ForEach(matchedCourses) { course in
                                NavigationLink(value: course.id) { CourseRow(course: course) }
                            }
                        }
                    }
                    Section {
                        NavigationLink(value: CatalogRoute(query: query)) {
                            Label("Search \u{201C}\(query)\u{201D} in the WeBeep catalogue", systemImage: "books.vertical")
                        }
                    }
                    Section(results.isEmpty ? "Files" : "\(results.count) files") {
                        if results.isEmpty && matchedCourses.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .frame(maxWidth: .infinity)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(results) { file in
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                if let course = file.course {
                                    Text(course.title).font(.caption.weight(.medium)).foregroundStyle(course.color).lineLimit(1)
                                }
                                FileRow(file: file, isNew: file.isNew(relativeTo: file.course?.lastSeenAt), showsLocation: true)
                            }
                        }
                    }
                }
            }
            .groupedList()
            // Empty states sit over the list, centred: as list rows they hug the top-left corner on the Mac.
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search everything", systemImage: "magnifyingglass", description: Text("File names, folders and courses across all your material."))
                }
            }
                        .selectionBar(selection, candidates: results)
            .animation(.snappy, value: selection.isActive)
            .environment(selection)
            .modifier(SelectionToolbar(selection: selection, canSelect: !results.isEmpty, hidesWhenEmpty: true))
            .onChange(of: results.map(\.key)) { _, _ in if results.isEmpty { selection.end() } }
            .sectionTitle("Search")
            .navigationDestination(for: Int.self) { CourseDetailView(courseID: $0) }
            .navigationDestination(for: CatalogRoute.self) { CatalogSearchView(initialQuery: $0.query) }
            .courseRoutes()
            #if os(macOS)
            .modifier(ToolbarSearch(search: search, prompt: "Files in every course"))
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
            // Opening the Search section puts the cursor in the field.
            .modifier(FocusWhenShown(search: search))
            #else
            .searchable(text: $query, prompt: "Files in every course")
            .searchFocused($searchFocused)
            // Opening the Search tab puts the cursor in the field (keyboard up on iPhone and iPad).
            .task(id: router.selectedTab) {
                guard router.selectedTab == .search else { return }
                try? await Task.sleep(for: .milliseconds(150))
                searchFocused = true
            }
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(FileTypeScope.allCases) { Text($0.label).tag($0) }
            }
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
            .task(id: "\(query)|\(scope.rawValue)") {
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let found = Self.files(matching: query.trimmingCharacters(in: .whitespaces), scope: scope, in: context)
                // New results replace the old ones without row animations: animating hundreds of
                // inserted and removed rows dominated each keystroke.
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) { results = found }
            }
        }
    }

    /// Files whose name, folder path or module name contains `q`, newest first. SQLite does the
    /// matching: walking every course's files on the main thread (and faulting each module)
    /// stalled typing for tens of milliseconds per keystroke.
    static func files(matching q: String, scope: FileTypeScope, in context: ModelContext) -> [FileItem] {
        let limit = 200
        var d = FetchDescriptor<FileItem>(
            predicate: #Predicate { file in
                file.filename.localizedStandardContains(q)
                    || file.filepath.localizedStandardContains(q)
                    || (file.module.flatMap { $0.name.localizedStandardContains(q) } ?? false)
            },
            sortBy: [SortDescriptor(\.timemodified, order: .reverse)])
        // The type scope is an extension check: fetch a margin, filter, keep the first `limit`.
        d.fetchLimit = scope == .all ? limit : limit * 4
        let found = (try? context.fetch(d)) ?? []
        return Array(found.lazy.filter { scope.matches($0.fileExtension) }.prefix(limit))
    }
}

#if os(macOS)
/// Moves the cursor into the search field whenever the section becomes visible. Reads only
/// `isActiveSection`, so switching sections does not re-render the search screen.
private struct FocusWhenShown: ViewModifier {
    let search: SearchText
    @Environment(\.isActiveSection) private var isActive
    func body(content: Content) -> some View {
        content.task(id: isActive) {
            guard isActive else { return }
            try? await Task.sleep(for: .milliseconds(150))
            search.focusRequest += 1
        }
    }
}
#endif
