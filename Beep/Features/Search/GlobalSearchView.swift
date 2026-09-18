import SwiftData
import SwiftUI

/// Search files across every course, plus courses by name.
struct GlobalSearchView: View {
    @Query(sort: \Course.title) private var courses: [Course]
    @State private var query = ""
    @State private var scope: FileTypeScope = .all
    @State private var results: [FileItem] = []

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    ContentUnavailableView("Search everything", systemImage: "magnifyingglass", description: Text("File names, folders and courses across all your material."))
                        .listRowBackground(Color.clear)
                } else {
                    let matchedCourses = courses.filter { $0.title.localizedCaseInsensitiveContains(query) || ($0.code?.contains(query) ?? false) }
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
                            ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
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
            .navigationTitle("Search")
            .navigationDestination(for: Int.self) { CourseDetailView(courseID: $0) }
            .navigationDestination(for: CatalogRoute.self) { CatalogSearchView(initialQuery: $0.query) }
            .courseRoutes()
            .searchable(text: $query, prompt: "Files in every course")
            .searchScopes($scope, activation: .onSearchPresentation) {
                ForEach(FileTypeScope.allCases) { Text($0.label).tag($0) }
            }
            .task(id: "\(query)|\(scope.rawValue)") {
                guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { results = []; return }
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let q = query.lowercased()
                results = courses.flatMap(\.files)
                    .filter { scope.matches($0.fileExtension) && ($0.filename.lowercased().contains(q) || $0.filepath.lowercased().contains(q) || ($0.module?.name.lowercased().contains(q) ?? false)) }
                    .sorted { $0.timemodified > $1.timemodified }
                    .prefix(200).map { $0 }
            }
        }
    }
}
