import SwiftData
import SwiftUI

/// Downloaded bytes and file count of one course.
struct CourseStorage: Identifiable {
    let course: Course
    let files: Int
    let bytes: Int
    var id: Int { course.id }
}

enum StorageUsage {
    /// Courses with at least one downloaded file, largest first. Sizes come from
    /// WeBeep's `filesize` of downloaded files: no disk walk, instant on 60+ courses.
    static func byCourse(_ courses: [Course]) -> [CourseStorage] {
        courses.compactMap { course in
            let downloaded = course.files.filter(\.isDownloaded)
            guard !downloaded.isEmpty else { return nil }
            return CourseStorage(course: course, files: downloaded.count, bytes: downloaded.reduce(0) { $0 + $1.filesize })
        }
        .sorted { $0.bytes == $1.bytes ? $0.course.title < $1.course.title : $0.bytes > $1.bytes }
    }
}

/// Space used per course, with a way to free it.
struct StorageView: View {
    @Environment(FileOpener.self) private var opener
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Course.title) private var courses: [Course]
    @State private var removeTarget: Course?

    private var usage: [CourseStorage] { StorageUsage.byCourse(courses) }

    var body: some View {
        let usage = usage
        let total = usage.reduce(0) { $0 + $1.bytes }
        List {
            Section {
                LabeledContent("Total", value: String(localized: "\(usage.reduce(0) { $0 + $1.files }) files · \(total.fileSizeLabel)"))
                    .monospacedDigit()
                Button("Show in Files app", systemImage: "folder") {
                    var comps = URLComponents(url: URL.documentsDirectory, resolvingAgainstBaseURL: false)
                    comps?.scheme = "shareddocuments"
                    if let url = comps?.url { openURL(url) }
                }
            }
            if usage.isEmpty {
                ContentUnavailableView("Nothing downloaded", systemImage: "internaldrive",
                                       description: Text("Files you download or that sync automatically show up here, course by course."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(usage) { item in
                        StorageRow(item: item, share: total > 0 ? Double(item.bytes) / Double(total) : 0)
                            .swipeActions(edge: .trailing) {
                                Button("Remove downloads", systemImage: "trash", role: .destructive) { removeTarget = item.course }
                            }
                            .contextMenu {
                                Button("Remove downloads", systemImage: "trash", role: .destructive) { removeTarget = item.course }
                            }
                    }
                } footer: {
                    Text("Courses with auto-download get new files again at the next sync. Turn auto-download off for a course to keep its space free.")
                }
            }
        }
        .groupedList()
        .navigationTitle("Storage by course")
        .inlineNavigationTitle()
        // `presenting:` hands the course to the button: dismissal clears `removeTarget`
        // before a plain closure could read it.
        .confirmationDialog(removeTarget.map { Text("Remove the downloads of \u{201C}\($0.title)\u{201D}?") } ?? Text(""),
                            isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
                            titleVisibility: .visible,
                            presenting: removeTarget) { course in
            Button("Remove downloads", role: .destructive) { remove(course) }
        } message: { _ in
            Text("The files are deleted from this device only. They stay on WeBeep and you can download them again anytime.")
        }
    }

    private func remove(_ course: Course) {
        for file in course.files where file.isDownloaded { opener.removeLocal(file) }
        try? context.save()
        removeTarget = nil
    }
}

private struct StorageRow: View {
    let item: CourseStorage
    let share: Double

    var body: some View {
        HStack(spacing: Theme.Spacing.m - 4) {
            CourseTile(monogram: item.course.monogram, color: item.course.color, size: 40)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(item.course.title).font(.body).lineLimit(2).truncationMode(.middle)
                ProgressView(value: share)
                    .progressViewStyle(.linear)
                    .tint(item.course.color)
                    .accessibilityHidden(true)
                Text("\(item.files) files").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: Theme.Spacing.s)
            Text(item.bytes.fileSizeLabel)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}
