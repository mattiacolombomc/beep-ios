import SwiftUI

/// A remote/local file. Tap opens it (downloading first if needed).
struct FileRow: View {
    let file: FileItem
    var isNew = false
    var title: String? = nil
    var showsLocation = false
    @Environment(FileOpener.self) private var opener

    private var subtitle: String {
        var parts: [String] = []
        if file.filesize > 0 { parts.append(ByteCountFormatter.string(fromByteCount: Int64(file.filesize), countStyle: .file)) }
        parts.append(file.timemodified.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    private var location: String? {
        guard showsLocation else { return nil }
        var parts: [String] = []
        if let s = file.module?.section?.name, !s.isEmpty { parts.append(s) }
        if let m = file.module?.name, file.module?.kind == .folder { parts.append(m) }
        let sub = file.filepath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !sub.isEmpty { parts.append(sub) }
        return parts.isEmpty ? nil : parts.joined(separator: " › ")
    }

    var body: some View {
        Button {
            opener.open(file)
        } label: {
            HStack(spacing: Theme.Spacing.m - 4) {
                FileTypeIcon(extension: file.fileExtension)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title ?? file.filename)
                        .font(.body)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if let location {
                        Text(location).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: Theme.Spacing.s)
                FileStateBadge(file: file, isNew: isNew)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Drag the real file into another app or window (iPad split view, Stage Manager).
        .onDrag { opener.itemProvider(for: file) }
        .contextMenu { FileContextMenu(file: file) }
        .swipeActions(edge: .trailing) {
            if file.isDownloaded {
                Button(role: .destructive) { opener.removeLocal(file) } label: { Label("Remove download", systemImage: "trash") }
            } else {
                Button { opener.download(file) } label: { Label("Download", systemImage: "arrow.down.circle") }.tint(.accentColor)
            }
        }
    }
}

struct FileStateBadge: View {
    let file: FileItem
    let isNew: Bool
    @Environment(FileOpener.self) private var opener

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if isNew {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                    .accessibilityLabel("New")
            }
            Group {
                switch file.state {
                case .downloading, .queued:
                    let p = opener.progress(for: file)
                    ProgressView(value: p)
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                case .downloaded:
                    Image(systemName: file.hasUpdate ? "arrow.triangle.2.circlepath.circle" : "checkmark.circle.fill")
                        .foregroundStyle(file.hasUpdate ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                case .failed:
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                case .notDownloaded:
                    Image(systemName: "icloud.and.arrow.down").foregroundStyle(.tertiary)
                }
            }
            .font(.body)
            .frame(width: 24, height: 24)
        }
    }
}

struct FileTypeIcon: View {
    let `extension`: String

    private var descriptor: (symbol: String, color: Color) {
        switch `extension` {
        case "pdf": ("doc.richtext.fill", .red)
        case "ppt", "pptx", "key", "odp": ("rectangle.on.rectangle.angled", .orange)
        case "doc", "docx", "odt", "rtf", "txt", "md": ("doc.text.fill", .blue)
        case "xls", "xlsx", "csv", "ods": ("tablecells.fill", .green)
        case "zip", "rar", "7z", "tar", "gz", "tgz": ("doc.zipper", .secondary)
        case "mp4", "mov", "m4v", "mkv", "avi", "webm": ("film.fill", .purple)
        case "mp3", "m4a", "wav": ("waveform", .purple)
        case "png", "jpg", "jpeg", "gif", "heic", "svg": ("photo.fill", .teal)
        case "py", "java", "c", "cpp", "h", "swift", "js", "ts", "ipynb", "m", "r", "sql", "tex": ("chevron.left.forwardslash.chevron.right", .indigo)
        case "html", "htm": ("globe", .blue)
        default: ("doc.fill", .secondary)
        }
    }

    var body: some View {
        Image(systemName: descriptor.symbol)
            .font(.title3)
            .foregroundStyle(descriptor.color)
            .accessibilityHidden(true)
    }
}

struct FileContextMenu: View {
    let file: FileItem
    @Environment(FileOpener.self) private var opener
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { opener.open(file) } label: { Label("Open", systemImage: "eye") }
        if file.isDownloaded {
            Button { opener.share(file) } label: { Label("Open in…", systemImage: "square.and.arrow.up") }
            Button { opener.showInFiles(file) } label: { Label("Show in Files", systemImage: "folder") }
            Divider()
            Button(role: .destructive) { opener.removeLocal(file) } label: { Label("Remove download", systemImage: "trash") }
        } else {
            Button { opener.download(file) } label: { Label("Download", systemImage: "arrow.down.circle") }
        }
        Divider()
        if let url = file.module?.url.flatMap(URL.init(string:)) {
            Button { openURL(url) } label: { Label("Open on WeBeep", systemImage: "safari") }
        }
    }
}
