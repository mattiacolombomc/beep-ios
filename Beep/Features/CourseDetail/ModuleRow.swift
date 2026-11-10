import SwiftUI

/// One Moodle module: a file, an expandable folder, a link, a page, a forum, a label.
struct ModuleRow: View {
    let module: CourseModule
    let course: Course
    let lastSeen: Date?
    var removedDisplay: RemovedDisplay = .grouped
    @Environment(\.openURL) private var openURL
    @State private var expanded = false

    var body: some View {
        switch module.kind {
        case .resource:
            // A resource gone from WeBeep shows the copy kept on disk.
            if let file = module.removedAt == nil ? module.liveFiles.first : module.keptRemovedFiles.first {
                FileRow(file: file, isNew: file.isNew(relativeTo: lastSeen), title: module.name)
            } else {
                GenericModuleRow(module: module, symbol: "doc")
            }
        case .folder:
            FolderTree(module: module, lastSeen: lastSeen, removedDisplay: removedDisplay)
        case .label:
            if let html = module.descriptionHTML {
                HTMLText(html: html)
                    .font(.subheadline)
                    .listRowBackground(Color.clear)
            } else {
                Text(module.name).font(.subheadline).foregroundStyle(.secondary)
            }
        case .url:
            Button {
                if let s = module.url, let url = URL(string: s) { openURL(url) }
            } label: {
                GenericModuleRow(module: module, symbol: "link", trailing: "arrow.up.right")
            }
            .buttonStyle(.plain)
        case .forum:
            NavigationLink(value: ForumRoute(module: module)) {
                GenericModuleRow(module: module, symbol: "bubble.left.and.bubble.right")
            }
        case .page:
            NavigationLink(value: PageRoute(module: module)) {
                GenericModuleRow(module: module, symbol: "doc.richtext")
            }
        case .lesson, .other:
            Button {
                if let s = module.url, let url = URL(string: s) { openURL(url) }
            } label: {
                GenericModuleRow(module: module, symbol: module.kind == .lesson ? "book" : "square.grid.2x2", trailing: "safari")
            }
            .buttonStyle(.plain)
        }
    }
}

struct ForumRoute: Hashable { let module: CourseModule }
struct PageRoute: Hashable { let module: CourseModule }

struct GenericModuleRow: View {
    let module: CourseModule
    let symbol: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.m - 4) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            Text(module.name)
                .font(.body)
                .lineLimit(2)
            Spacer(minLength: Theme.Spacing.s)
            if let trailing {
                Image(systemName: trailing).font(.footnote).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Closed group at the bottom of a folder or section: what the teacher removed from WeBeep
/// and Beep still has on disk.
struct RemovedGroup<Content: View>: View {
    let count: Int
    @ViewBuilder var content: Content
    @State private var isOpen = DemoData.showsRemovedSample

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            if isOpen { content }
        } label: {
            HStack(spacing: Theme.Spacing.m - 4) {
                Image(systemName: "archivebox")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                Text("Removed from WeBeep").foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.s)
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Folder module: root files + one expandable group per sub-path.
struct FolderTree: View {
    let module: CourseModule
    let lastSeen: Date?
    var removedDisplay: RemovedDisplay = .grouped
    @Environment(SyncEngine.self) private var sync
    @Environment(FileOpener.self) private var opener
    @State private var expandedPaths: Set<String> = []
    @State private var isOpen = DemoData.showsRemovedSample

    /// Files listed in the folder: the ones on WeBeep, plus the kept removed ones when they are
    /// shown in place. A folder that is itself gone from WeBeep lists what was kept of it.
    private var listed: [FileItem] {
        if module.removedAt != nil { return module.keptRemovedFiles }
        return removedDisplay == .inline ? module.files.filter { !$0.isRemoved || $0.isKeptRemoved } : module.liveFiles
    }
    /// Kept removed files shown in their own group at the bottom.
    private var removed: [FileItem] {
        module.removedAt == nil && removedDisplay == .grouped ? Self.sorted(module.keptRemovedFiles) : []
    }
    private static func sorted(_ files: [FileItem]) -> [FileItem] {
        files.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }
    private var files: [FileItem] { Self.sorted(listed) }
    private var newCount: Int { module.liveFiles.reduce(0) { $0 + ($1.isNew(relativeTo: lastSeen) ? 1 : 0) } }

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            // Built only when open: every folder of a course sorted its files on each render.
            if isOpen {
                let sorted = files
                let subPaths = Array(Set(sorted.map(\.filepath).filter { $0 != "/" && !$0.isEmpty })).sorted()
                ForEach(sorted.filter { $0.filepath == "/" || $0.filepath.isEmpty }) { file in
                    FileRow(file: file, isNew: file.isNew(relativeTo: lastSeen))
                }
                ForEach(subPaths, id: \.self) { path in
                    DisclosureGroup(isExpanded: binding(path)) {
                        ForEach(sorted.filter { $0.filepath == path }) { file in
                            FileRow(file: file, isNew: file.isNew(relativeTo: lastSeen))
                        }
                    } label: {
                        Label(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), systemImage: "folder")
                    }
                    .contextMenu {
                        let inPath = module.liveFiles.filter { $0.filepath.hasPrefix(path) }
                        SelectFolderButton(files: inPath)
                        Button { sync.downloads.enqueue(inPath) } label: { Label("Download folder", systemImage: "arrow.down.circle") }
                    }
                }
                let gone = removed
                if !gone.isEmpty {
                    RemovedGroup(count: gone.count) {
                        ForEach(gone) { file in FileRow(file: file) }
                    }
                }
            }
        } label: {
            HStack(spacing: Theme.Spacing.m - 4) {
                Image(systemName: isOpen ? "folder.fill" : "folder")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)
                    .contentTransition(.symbolEffect(.replace))
                Text(module.name).lineLimit(2)
                Spacer(minLength: Theme.Spacing.s)
                if newCount > 0 {
                    Text("\(newCount)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.accentColor, in: .capsule)
                }
                Text("\(listed.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.18), value: isOpen)
        .contextMenu {
            SelectFolderButton(files: module.liveFiles)
            Button { sync.downloads.enqueue(module.liveFiles) } label: { Label("Download folder", systemImage: "arrow.down.circle") }
            #if os(macOS)
            if let dir = opener.directory(of: module) {
                Button { opener.reveal(dir) } label: { Label("Show in Finder", systemImage: "folder") }
            }
            #endif
        }
    }

    private func binding(_ path: String) -> Binding<Bool> {
        Binding(get: { expandedPaths.contains(path) },
                set: { if $0 { expandedPaths.insert(path) } else { expandedPaths.remove(path) } })
    }
}

/// Renders simple Moodle HTML (labels, previews) as plain paragraphs. Fast: no WebKit.
struct HTMLText: View {
    let html: String

    /// Tag-stripped, entity-decoded single paragraph (for previews).
    static func plain(_ html: String) -> String {
        paragraphs(html).replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tag-stripped text keeping paragraph breaks.
    static func paragraphs(_ html: String) -> String {
        var s = html.replacing(/<br\s*\/?>/, with: "\n")
        s = s.replacing(/<\/(p|div|li|h[1-6]|tr)>/, with: "\n")
        s = s.replacing(/<li[^>]*>/, with: "• ")
        s = s.replacing(/<[^>]+>/, with: "")
        for (e, c) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"), ("&egrave;", "è"), ("&agrave;", "à"), ("&ograve;", "ò"), ("&ugrave;", "ù"), ("&igrave;", "ì"), ("&eacute;", "é")] {
            s = s.replacingOccurrences(of: e, with: c)
        }
        s = s.replacing(/\n{3,}/, with: "\n\n")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Text(Self.paragraphs(html))
    }
}

/// "Select Folder" in a folder's context menu: selects every file in it (starting multi-select if
/// needed), or deselects them when they are all selected already.
private struct SelectFolderButton: View {
    let files: [FileItem]
    @Environment(FileSelection.self) private var selection: FileSelection?

    var body: some View {
        if let selection, !files.isEmpty {
            if selection.isActive && selection.allSelected(in: files) {
                Button { withAnimation(.snappy) { selection.deselect(files) } } label: { Label("Deselect Folder", systemImage: "circle") }
            } else {
                Button { withAnimation(.snappy) { selection.select(files) } } label: { Label("Select Folder", systemImage: "checkmark.circle") }
            }
            Divider()
        }
    }
}
