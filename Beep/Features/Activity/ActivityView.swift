import SwiftData
import SwiftUI

/// Downloads in flight, queued, failed, and the last sync report.
struct ActivityView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(AppSession.self) private var session
    @Query(filter: #Predicate<FileItem> { $0.stateRaw == 1 || $0.stateRaw == 2 }, sort: \FileItem.filename) private var active: [FileItem]
    @Query(filter: #Predicate<FileItem> { $0.stateRaw == 4 }, sort: \FileItem.filename) private var failed: [FileItem]
    /// The 100 shown: fetching every downloaded file (hundreds) re-ran on each sync save.
    private static var recentDownloads: FetchDescriptor<FileItem> {
        var d = FetchDescriptor<FileItem>(predicate: #Predicate { $0.stateRaw == 3 }, sortBy: [SortDescriptor(\.timemodified, order: .reverse)])
        d.fetchLimit = 100
        return d
    }
    @Query(ActivityView.recentDownloads) private var downloaded: [FileItem]

    var body: some View {
        NavigationStack {
            List {
                // Bento summary, the same tiles as the course list header.
                Section {
                    ActivitySummary()
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)
                if let errors = sync.lastReport?.errors, !errors.isEmpty {
                    Section {
                        DisclosureGroup("\(errors.count) errors") {
                            ForEach(errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if !active.isEmpty {
                    Section {
                        ForEach(active) { FileRow(file: $0, showsLocation: true) }
                    } header: {
                        HStack {
                            Text("Downloading")
                            Spacer()
                            Text("\(sync.downloads.progress.completedInSession)/\(sync.downloads.progress.total)").monospacedDigit()
                            Button("Cancel all", role: .destructive) { sync.downloads.cancelAll() }
                                .font(.caption)
                        }
                    }
                }
                if !failed.isEmpty {
                    Section("Failed") { ForEach(failed) { FileRow(file: $0, showsLocation: true) } }
                }
                Section {
                    if downloaded.isEmpty {
                        ContentUnavailableView("No downloads yet", systemImage: "arrow.down.circle", description: Text("Files you open or download appear here and in the Files app."))
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(downloaded) { FileRow(file: $0, showsLocation: true) }
                    }
                } header: {
                    Text("Downloaded")
                }
            }
            .groupedList()
            .sectionTitle("Activity")
            .refreshable {
                if let client = session.client, let user = session.user { _ = await sync.syncAll(client: client, userID: user.id) }
            }
        }
    }
}

/// Sync and download status as a grid of tiles, adapting to the window width.
private struct ActivitySummary: View {
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        let report = sync.lastReport
        let downloads = sync.downloads.progress
        LazyVGrid(columns: columns, spacing: Theme.Spacing.s) {
            StatusTile(symbol: syncSymbol, title: "Sync", value: syncValue, detail: syncDetail,
                       tint: sync.isIndexing ? .accentColor : .secondary, isProminent: sync.isIndexing)
            StatusTile(symbol: "books.vertical", title: "Courses updated", value: count(report?.coursesIndexed),
                       detail: "Last sync", tint: .secondary)
            StatusTile(symbol: "sparkles", title: "New files", value: count(report?.newFiles),
                       detail: "Last sync", tint: (report?.newFiles ?? 0) > 0 ? .accentColor : .secondary)
            StatusTile(symbol: "arrow.clockwise.circle", title: "Updated files",
                       value: count(report?.updatedFiles), detail: "Last sync", tint: .secondary)
            StatusTile(symbol: "arrow.down.circle", title: "Downloads",
                       value: downloads.isBusy ? "\(downloads.completedInSession)/\(downloads.total)" : count(report?.queuedDownloads),
                       detail: downloads.isBusy ? "Downloading…" : "Queued downloads",
                       tint: downloads.isBusy ? .accentColor : .secondary, isProminent: downloads.isBusy)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
    }

    /// Five equal tiles across the window on the Mac; as many as fit on iPhone and iPad.
    private var columns: [GridItem] {
        #if os(macOS)
        Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: 5)
        #else
        [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.s)]
        #endif
    }

    /// "—" until a sync has run since launch: zero would claim nothing changed.
    private func count(_ value: Int?) -> String { value.map(String.init) ?? "—" }

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
            if let at = sync.lastReport?.finishedAt ?? sync.lastSyncAt { return at.formatted(date: .omitted, time: .shortened) }
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
