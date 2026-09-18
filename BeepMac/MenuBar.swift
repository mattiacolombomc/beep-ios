import SwiftData
import SwiftUI

/// Menu bar icon: the Beep glyph, animated while a sync runs, with a dot when there's new material.
struct MenuBarIcon: View {
    let sync: SyncEngine

    var body: some View {
        Image(systemName: sync.isRunning ? "arrow.triangle.2.circlepath" : "graduationcap")
            .symbolEffect(.rotate, isActive: sync.isRunning)
    }
}

/// Menu bar panel: status, newest files, quick actions. Beep keeps syncing from here
/// while the main window is closed, which is what WeBeep Sync users expect.
struct MenuBarContent: View {
    let folder: DownloadFolder
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(FileOpener.self) private var opener
    @Environment(AppRouter.self) private var router
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Query(Self.latestDescriptor) private var latest: [FileItem]
    @Query private var courses: [Course]

    private static var latestDescriptor: FetchDescriptor<FileItem> {
        var d = FetchDescriptor<FileItem>(sortBy: [SortDescriptor(\.timemodified, order: .reverse)])
        d.fetchLimit = 6
        return d
    }
    private var newCount: Int { courses.reduce(0) { $0 + $1.newFilesCount } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Beep").font(.headline)
                    Text(statusLine).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                SyncButton()
                    .buttonStyle(.borderless)
                    .labelStyle(.iconOnly)
            }

            if newCount == 0 {
                Label("You're up to date", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Label("\(newCount) new files", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            }
            if !latest.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest files").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(latest) { file in
                        Button {
                            opener.open(file)
                        } label: {
                            HStack {
                                FileTypeIcon(extension: file.fileExtension).frame(width: 22)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(file.filename).lineLimit(1).truncationMode(.middle)
                                    Text(file.course?.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Button("Open Beep", systemImage: "macwindow") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Button("Open Download Folder", systemImage: "folder") { folder.showInFinder() }
                    .disabled(!folder.isChosen)
                Button("Settings…", systemImage: "gearshape") {
                    NSApp.activate()
                    openSettings()
                }
                Button("Quit Beep", systemImage: "power") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
        }
        .padding(Theme.Spacing.m)
        .frame(width: 320)
    }

    private var statusLine: String {
        switch sync.phase {
        case .indexing(let done, let total, _): return String(localized: "Updating courses… \(done)/\(total)")
        case .failed: return String(localized: "Last sync failed")
        case .idle:
            if let at = sync.lastSyncAt { return String(localized: "Updated \(at.relativeLabel)") }
            return String(localized: "Never synced")
        }
    }
}
