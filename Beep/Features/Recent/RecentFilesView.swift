import SwiftData
import SwiftUI

/// Cross-course feed of files by modification date.
struct RecentFilesView: View {
    @Query(sort: \FileItem.timemodified, order: .reverse) private var files: [FileItem]

    private var grouped: [(day: Date, files: [FileItem])] {
        let recent = Array(files.prefix(300))
        let cal = Calendar.current
        return Dictionary(grouping: recent) { cal.startOfDay(for: $0.timemodified) }
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack {
            List {
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
            .listStyle(.insetGrouped)
            .navigationTitle("Recent")
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
