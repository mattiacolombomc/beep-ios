import SwiftUI

/// One Moodle module: a file, an expandable folder, a link, a page, a forum, a label.
struct ModuleRow: View {
    let module: CourseModule
    let course: Course
    let lastSeen: Date?
    @Environment(\.openURL) private var openURL
    @State private var expanded = false

    var body: some View {
        switch module.kind {
        case .resource:
            if let file = module.files.first {
                FileRow(file: file, isNew: file.isNew(relativeTo: lastSeen), title: module.name)
            } else {
                GenericModuleRow(module: module, symbol: "doc")
            }
        case .folder:
            FolderTree(module: module, lastSeen: lastSeen)
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

/// Folder module: root files + one expandable group per sub-path.
struct FolderTree: View {
    let module: CourseModule
    let lastSeen: Date?
    @State private var expandedPaths: Set<String> = []
    @State private var isOpen = false

    private var files: [FileItem] { module.files.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending } }
    private var rootFiles: [FileItem] { files.filter { $0.filepath == "/" || $0.filepath.isEmpty } }
    private var subPaths: [String] {
        Array(Set(files.map(\.filepath).filter { $0 != "/" && !$0.isEmpty })).sorted()
    }
    private var newCount: Int { module.files.reduce(0) { $0 + ($1.isNew(relativeTo: lastSeen) ? 1 : 0) } }

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            ForEach(rootFiles) { file in
                FileRow(file: file, isNew: file.isNew(relativeTo: lastSeen))
            }
            ForEach(subPaths, id: \.self) { path in
                DisclosureGroup(isExpanded: binding(path)) {
                    ForEach(files.filter { $0.filepath == path }) { file in
                        FileRow(file: file, isNew: file.isNew(relativeTo: lastSeen))
                    }
                } label: {
                    Label(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), systemImage: "folder")
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
                Text("\(module.files.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .animation(.spring(duration: 0.32, bounce: 0.18), value: isOpen)
    }

    private func binding(_ path: String) -> Binding<Bool> {
        Binding(get: { expandedPaths.contains(path) },
                set: { if $0 { expandedPaths.insert(path) } else { expandedPaths.remove(path) } })
    }
}

/// Renders simple Moodle HTML (labels, descriptions) as attributed text.
struct HTMLText: View {
    let html: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        let data = Data(html.utf8)
        if let ns = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) {
            var a = AttributedString(ns)
            a.font = nil
            a.foregroundColor = nil
            return a
        }
        return AttributedString(html.replacing(/<[^>]+>/, with: ""))
    }
}
