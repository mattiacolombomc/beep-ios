import SwiftUI

/// Window-wide bottom bar: where Beep is syncing, always visible, one click to Finder.
struct SyncFolderBar: View {
    @Environment(DownloadFolder.self) private var folder
    @Environment(SyncEngine.self) private var sync
    @State private var picking = false

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: folder.isChosen ? "folder.fill" : "folder.badge.questionmark")
                .foregroundStyle(folder.isChosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.orange))
            if let url = folder.url {
                Button {
                    folder.showInFinder()
                } label: {
                    Text(url.path(percentEncoded: false).abbreviatingHome)
                        .font(.callout.monospaced())
                        .lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.link)
                .help("Show in Finder")
            } else {
                Text("Choose where Beep saves your courses").font(.callout).foregroundStyle(.orange)
            }
            Spacer(minLength: Theme.Spacing.m)
            if case .indexing(let done, let total, _) = sync.phase {
                Text("Updating courses… \(done)/\(total)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else if sync.downloads.progress.isBusy {
                Text("Downloading…").font(.caption).foregroundStyle(.secondary)
            }
            Button(folder.isChosen ? "Change…" : "Choose Folder…") { picking = true }
                .controlSize(.small)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder.choose(url) }
        }
    }
}
