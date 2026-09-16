import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.title) private var courses: [Course]
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section {
                        HStack(spacing: Theme.Spacing.m - 4) {
                            AsyncImage(url: user.pictureURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(.secondary)
                            }
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.fullname.isEmpty ? "Signed in" : user.fullname).font(.headline)
                                Text(user.username).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    NavigationLink {
                        SyncCoursesView()
                    } label: {
                        LabeledContent("Auto-download courses", value: "\(courses.filter(\.syncEnabled).count)")
                    }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("New files in these courses download automatically when you sync.")
                }
                Section("About") {
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    LabeledContent("Version", value: Bundle.main.versionString)
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Sign out of WeBeep?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { session.signOut(); dismiss() }
            } message: {
                Text("Downloaded files stay on this device.")
            }
        }
    }
}

struct SyncCoursesView: View {
    @Query(sort: \Course.title) private var courses: [Course]

    var body: some View {
        List {
            ForEach(courses.filter { !$0.isHidden }) { course in
                @Bindable var course = course
                Toggle(isOn: $course.syncEnabled) {
                    HStack(spacing: Theme.Spacing.m - 4) {
                        CourseTile(monogram: course.monogram, color: course.color, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.title).font(.body).lineLimit(1)
                            Text(course.categoryName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Auto-download")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Beep is inspired by and partly derived from **myPoliFile** by Matteo Visotto, released under the MIT License.")
                Text("The login flow follows the approach of **WeBeep Sync** by Tommaso Morganti.")
                Text("Beep is not affiliated with, endorsed by, or sponsored by Politecnico di Milano.")
                    .foregroundStyle(.secondary)
                if let notice = Bundle.main.url(forResource: "NOTICE", withExtension: nil), let text = try? String(contentsOf: notice, encoding: .utf8) {
                    Text(text).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(Theme.Spacing.m)
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Bundle {
    var versionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
