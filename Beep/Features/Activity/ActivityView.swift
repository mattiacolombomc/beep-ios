import SwiftData
import SwiftUI

/// Downloads in flight, queued, failed, and the last sync report.
struct ActivityView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(AppSession.self) private var session
    @Query(filter: #Predicate<FileItem> { $0.stateRaw == 1 || $0.stateRaw == 2 }, sort: \FileItem.filename) private var active: [FileItem]
    @Query(filter: #Predicate<FileItem> { $0.stateRaw == 4 }, sort: \FileItem.filename) private var failed: [FileItem]
    @Query(filter: #Predicate<FileItem> { $0.stateRaw == 3 }, sort: \FileItem.timemodified, order: .reverse) private var downloaded: [FileItem]

    var body: some View {
        NavigationStack {
            List {
                if case .indexing(let done, let total, let current) = sync.phase {
                    Section("Syncing now") {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            HStack {
                                Text(current ?? String(localized: "Loading courses…")).font(.headline).lineLimit(1)
                                Spacer()
                                Text("\(done)/\(total)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            ProgressView(value: total > 0 ? Double(done) / Double(total) : 0)
                        }
                        .padding(.vertical, Theme.Spacing.xs)
                    }
                }
                if let report = sync.lastReport {
                    Section("Last sync") {
                        LabeledContent("Courses updated", value: "\(report.coursesIndexed)")
                        LabeledContent("New files", value: "\(report.newFiles)")
                        LabeledContent("Updated files", value: "\(report.updatedFiles)")
                        LabeledContent("Queued downloads", value: "\(report.queuedDownloads)")
                        if !report.errors.isEmpty {
                            DisclosureGroup("\(report.errors.count) errors") {
                                ForEach(report.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        LabeledContent("Finished", value: report.finishedAt.formatted(date: .omitted, time: .shortened))
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
                        ForEach(downloaded.prefix(100)) { FileRow(file: $0, showsLocation: true) }
                    }
                } header: {
                    Text("Downloaded")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Activity")
            .refreshable {
                if let client = session.client, let user = session.user { _ = await sync.syncAll(client: client, userID: user.id) }
            }
        }
    }
}
