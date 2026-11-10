import SwiftData
import SwiftUI

/// Cross-course feed of files by modification date.
struct RecentFilesView: View {
    /// Only the newest 300 files: the feed never needs the whole store, and a bounded
    /// query keeps every re-evaluation during a sync cheap.
    private static var recent: FetchDescriptor<FileItem> {
        var d = FetchDescriptor<FileItem>(predicate: #Predicate { $0.removedAt == nil }, sortBy: [SortDescriptor(\.timemodified, order: .reverse)])
        d.fetchLimit = 300
        return d
    }
    @Query(RecentFilesView.recent) private var files: [FileItem]
    @State private var selection = FileSelection()

    private var grouped: [(day: Date, files: [FileItem])] {
        let recent = files
        let cal = Calendar.current
        return Dictionary(grouping: recent) { cal.startOfDay(for: $0.timemodified) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
                MarkAllSeenRow()
                if files.isEmpty {
                    ContentUnavailableView("Nothing yet", systemImage: "clock", description: Text("Once your courses are synced, the latest files from every course show up here."))
                        .listRowBackground(Color.clear)
                }
                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.files) { file in
                            RecentFileRow(file: file)
                        }
                    } header: {
                        Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide))
                    }
                }
            }
            .groupedList()
                        .selectionBar(selection, candidates: files)
            .animation(.snappy, value: selection.isActive)
            .environment(selection)
            .sectionTitle("Recent")
            #if os(macOS)
            .windowToolbar(selection: selection, canSelect: !files.isEmpty)
            #else
            .modifier(SelectionToolbar(selection: selection, canSelect: !files.isEmpty))
            #endif
            .onDisappear { selection.end() }
        }
    }
}

/// "Mark all as seen", shown while some course has new files. Its own view, so that the course
/// query re-renders this row and not the whole feed.
private struct MarkAllSeenRow: View {
    @Query(filter: #Predicate<Course> { $0.newFilesCount > 0 }) private var courses: [Course]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let count = courses.reduce(0) { $0 + $1.newFilesCount }
        if count > 0 {
            Section {
                Button {
                    withAnimation(.snappy) { _ = try? Course.markAllSeen(in: modelContext) }
                } label: {
                    HStack(spacing: Theme.Spacing.m - 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text("Mark all as seen")
                            Text("\(count) new files").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct RecentFileRow: View {
    let file: FileItem
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let course = file.course {
                HStack(spacing: 6) {
                    Circle().fill(course.color).frame(width: 8, height: 8)
                    Text(course.title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            FileRow(file: file, isNew: file.isNew(relativeTo: file.course?.lastSeenAt), showsLocation: true)
        }
    }
}
