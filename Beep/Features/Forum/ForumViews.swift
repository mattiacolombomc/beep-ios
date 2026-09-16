import SwiftUI

/// Read-only forum: discussions of a module, then the posts of one discussion.
struct ForumDiscussionsView: View {
    let module: CourseModule
    @Environment(AppSession.self) private var session
    @State private var discussions: [DiscussionDTO] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(.secondary) }
            }
            if !isLoading && discussions.isEmpty && error == nil {
                ContentUnavailableView("No posts yet", systemImage: "bubble.left.and.bubble.right", description: Text("Nothing has been posted in this forum."))
                    .listRowBackground(Color.clear)
            }
            ForEach(discussions, id: \.id) { d in
                NavigationLink(value: DiscussionRoute(discussion: d, forumName: module.name)) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            if d.pinned == true { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                            Text(Multilang.resolve(d.subject, language: language)).font(.headline).lineLimit(2)
                        }
                        Text(HTMLText.plain(d.message)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        HStack(spacing: Theme.Spacing.s) {
                            Text(d.userfullname ?? "").lineLimit(1)
                            Text("·")
                            Text(Date(timeIntervalSince1970: TimeInterval(d.modified ?? d.created ?? 0)), format: .relative(presentation: .named))
                            if let n = d.numreplies, n > 0 {
                                Text("·")
                                Label("\(n)", systemImage: "arrowshape.turn.up.left").labelStyle(.titleAndIcon)
                            }
                        }
                        .font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(module.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if isLoading { ProgressView() } }
        .refreshable { await load() }
        .task { await load() }
    }

    private var language: String { Locale.current.language.languageCode?.identifier ?? "en" }

    private func load() async {
        guard let client = session.client, let forumID = module.instance, !DemoData.isEnabled else { isLoading = false; return }
        isLoading = true
        defer { isLoading = false }
        do {
            discussions = try await client.forumDiscussions(forumID: forumID).discussions
            error = nil
        } catch MoodleError.invalidToken {
            session.signOut()
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct DiscussionRoute: Hashable {
    let discussion: DiscussionDTO
    let forumName: String
}

extension DiscussionDTO: Hashable {
    static func == (lhs: DiscussionDTO, rhs: DiscussionDTO) -> Bool { lhs.id == rhs.id && lhs.modified == rhs.modified }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct DiscussionView: View {
    let route: DiscussionRoute
    @Environment(AppSession.self) private var session
    @State private var posts: [PostDTO]?

    private var language: String { Locale.current.language.languageCode?.identifier ?? "en" }

    var body: some View {
        Group {
            if let posts {
                HTMLDocumentView(
                    title: Multilang.resolve(route.discussion.subject, language: language),
                    meta: meta(author: route.discussion.userfullname, date: route.discussion.created ?? route.discussion.modified),
                    bodyHTML: Multilang.resolve(route.discussion.message, language: language),
                    extraSections: posts
                        .filter { ($0.parentid ?? 0) != 0 }
                        .sorted { ($0.timecreated ?? 0) < ($1.timecreated ?? 0) }
                        .map { (heading: Multilang.resolve($0.subject, language: language),
                                meta: meta(author: $0.author?.fullname, date: $0.timecreated ?? $0.timemodified),
                                html: Multilang.resolve($0.message, language: language)) }
                )
                .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(route.forumName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let client = session.client, !DemoData.isEnabled else { posts = []; return }
            posts = (try? await client.discussionPosts(discussionID: route.discussion.discussion).posts) ?? []
        }
    }

    private func meta(author: String?, date: Int?) -> String {
        var parts: [String] = []
        if let author, !author.isEmpty { parts.append(author) }
        if let date { parts.append(Date(timeIntervalSince1970: TimeInterval(date)).formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }
}
