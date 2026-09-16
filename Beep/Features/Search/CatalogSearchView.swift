import SwiftData
import SwiftUI

struct CatalogRoute: Hashable { let query: String }

/// Search the whole WeBeep catalogue and self-enrol.
struct CatalogSearchView: View {
    let initialQuery: String
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Query private var enrolled: [Course]
    @State private var query = ""
    @State private var results: [CatalogCourseDTO] = []
    @State private var total = 0
    @State private var isLoading = false
    @State private var error: String?
    @State private var enrolTarget: CatalogCourseDTO?
    @State private var enrolling: Int?
    @State private var enrolMessage: String?

    init(initialQuery: String) {
        self.initialQuery = initialQuery
        _query = State(initialValue: initialQuery)
    }

    private var enrolledIDs: Set<Int> { Set(enrolled.map(\.id)) }

    var body: some View {
        List {
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("Find other courses", systemImage: "books.vertical", description: Text("Search the WeBeep catalogue by name or code and enrol from here."))
                    .listRowBackground(Color.clear)
            } else if results.isEmpty && !isLoading && error == nil {
                ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
            }
            if !results.isEmpty {
                Section {
                    ForEach(results) { c in
                        CatalogRow(course: c, isEnrolled: enrolledIDs.contains(c.id), isEnrolling: enrolling == c.id) {
                            enrolTarget = c
                        }
                    }
                } header: {
                    Text(total > results.count ? "First \(results.count) of \(total)" : "\(results.count) courses")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("WeBeep catalogue")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Course name or code")
        .overlay { if isLoading && results.isEmpty { ProgressView() } }
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 3 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await search(q)
        }
        .confirmationDialog(enrolTarget.map { Text("Enrol in \u{201C}\(CourseNameParser.parse($0.displayname).name)\u{201D}?") } ?? Text(""),
                            isPresented: Binding(get: { enrolTarget != nil }, set: { if !$0 { enrolTarget = nil } }), titleVisibility: .visible) {
            if let c = enrolTarget {
                Button("Enrol") { Task { await enrol(c) } }
            }
        } message: {
            Text("You will be enrolled on WeBeep with your account, exactly as from the website. Courses that need an enrolment key cannot be joined from here.")
        }
        .alert("Enrolment", isPresented: Binding(get: { enrolMessage != nil }, set: { if !$0 { enrolMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(enrolMessage ?? "") }
    }

    private func search(_ q: String) async {
        guard let client = session.client, !DemoData.isEnabled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let dto = try await client.searchCatalog(q)
            results = dto.courses
            total = dto.total
            error = nil
        } catch MoodleError.invalidToken {
            session.signOut()
        } catch {
            self.error = String(describing: error)
        }
    }

    private func enrol(_ c: CatalogCourseDTO) async {
        guard let client = session.client, let user = session.user else { return }
        enrolling = c.id
        defer { enrolling = nil }
        do {
            let result = try await client.enrolSelf(courseID: c.id)
            if result.status {
                enrolMessage = String(localized: "Enrolled. The course is being added to your list.")
                _ = await sync.syncAll(client: client, userID: user.id, trigger: .manual)
            } else {
                enrolMessage = result.warnings?.compactMap(\.message).first ?? String(localized: "WeBeep refused the enrolment.")
            }
        } catch {
            enrolMessage = String(describing: error)
        }
    }
}

private struct CatalogRow: View {
    let course: CatalogCourseDTO
    let isEnrolled: Bool
    let isEnrolling: Bool
    let enrol: () -> Void

    var body: some View {
        let title = CourseNameParser.parse(course.displayname)
        HStack(spacing: Theme.Spacing.m - 4) {
            CourseTile(monogram: CourseMonogram.make(title.name), color: Theme.courseColor(id: course.id))
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title.name).font(.headline).lineLimit(2)
                Text([title.code, title.professors, course.categoryname].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.s)
            if isEnrolled {
                Label("Enrolled", systemImage: "checkmark.circle.fill").labelStyle(.iconOnly).foregroundStyle(.tint)
            } else if isEnrolling {
                ProgressView().controlSize(.small)
            } else {
                Button("Enrol", action: enrol)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
