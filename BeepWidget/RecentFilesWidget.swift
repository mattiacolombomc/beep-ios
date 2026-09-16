import SwiftData
import SwiftUI
import WidgetKit

struct RecentFileEntry: TimelineEntry {
    struct Item: Identifiable {
        let id: String
        let filename: String
        let courseTitle: String
        let monogram: String
        let colorIndex: Int
        let date: Date
        let isNew: Bool
    }
    let date: Date
    let items: [Item]
    let newCount: Int
    let lastSync: Date?
}

struct RecentFilesProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentFileEntry {
        RecentFileEntry(date: .now, items: (0..<3).map {
            .init(id: "\($0)", filename: "Lecture 0\($0 + 1).pdf", courseTitle: "Distributed Systems", monogram: "DS", colorIndex: $0, date: .now, isNew: $0 == 0)
        }, newCount: 1, lastSync: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentFileEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecentFileEntry>) -> Void) {
        let entry = load()
        completion(Timeline(entries: [entry], policy: .after(Date.now.addingTimeInterval(30 * 60))))
    }

    private func load() -> RecentFileEntry {
        let lastSync = UserDefaults(suiteName: StoreContainer.appGroup)?.object(forKey: "lastSyncAt") as? Date
        guard let container = try? StoreContainer.make() else {
            return RecentFileEntry(date: .now, items: [], newCount: 0, lastSync: lastSync)
        }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<FileItem>(sortBy: [SortDescriptor(\.timemodified, order: .reverse)])
        descriptor.fetchLimit = 8
        let files = (try? context.fetch(descriptor)) ?? []
        let courses = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        let newCount = courses.reduce(0) { $0 + $1.newFilesCount }
        let items = files.map { f in
            RecentFileEntry.Item(id: f.key, filename: f.filename, courseTitle: f.course?.title ?? "",
                                 monogram: f.course?.monogram ?? "", colorIndex: f.course?.id ?? 0,
                                 date: f.timemodified, isNew: f.isNew(relativeTo: f.course?.lastSeenAt))
        }
        return RecentFileEntry(date: .now, items: items, newCount: newCount, lastSync: lastSync)
    }
}

struct RecentFilesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentFiles", provider: RecentFilesProvider()) { entry in
            RecentFilesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Latest material")
        .description("The newest files from your WeBeep courses.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentFilesView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RecentFileEntry

    private var rows: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        switch family {
        case .systemSmall: small
        default: list
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.tint)
                Text("\(entry.newCount)").font(.title.weight(.bold)).monospacedDigit()
                Spacer()
            }
            Text(entry.newCount == 1 ? "new file" : "new files").font(.caption.weight(.medium))
            Spacer(minLength: 0)
            if let first = entry.items.first {
                Text(first.filename).font(.caption2).lineLimit(2).foregroundStyle(.secondary)
                Text(first.courseTitle).font(.caption2).lineLimit(1).foregroundStyle(Theme.courseColor(id: first.colorIndex))
            } else {
                Text("Nothing synced yet").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .widgetURL(entry.items.first.map { AppRouter.fileURL(key: $0.id) } ?? URL(string: "beep://sync")!)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Latest material", systemImage: "graduationcap.fill")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if let s = entry.lastSync {
                    Text(s, format: .relative(presentation: .named)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if entry.items.isEmpty {
                Text("Open Beep to sync your courses.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(entry.items.prefix(rows)) { item in
                Link(destination: AppRouter.fileURL(key: item.id)) {
                    HStack(spacing: 8) {
                        Text(item.monogram)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Theme.courseColor(id: item.colorIndex).gradient, in: .rect(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.filename).font(.caption.weight(.medium)).lineLimit(1)
                            Text(item.courseTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        if item.isNew { Circle().fill(.tint).frame(width: 6, height: 6) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
