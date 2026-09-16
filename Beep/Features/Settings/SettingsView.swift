import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.title) private var courses: [Course]
    @State private var confirmSignOut = false
    @Environment(\.openURL) private var openURL
    @AppStorage("settings.backgroundRefresh") private var backgroundRefresh = true
    @AppStorage("settings.notifications") private var notifications = true

    private var downloadedFiles: [FileItem] { courses.flatMap(\.files).filter(\.isDownloaded) }
    private var downloadedCount: Int { downloadedFiles.count }
    private var downloadedSize: Int { downloadedFiles.reduce(0) { $0 + $1.filesize } }

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
                    Toggle("Check in the background", systemImage: "clock.arrow.2.circlepath", isOn: $backgroundRefresh)
                        .onChange(of: backgroundRefresh) { _, on in on ? BackgroundRefresh.schedule() : BackgroundRefresh.cancel() }
                    Toggle("Notify about new files", systemImage: "bell.badge", isOn: $notifications)
                        .onChange(of: notifications) { _, on in
                            if on { Task { notifications = await Notifier.requestPermission() } }
                        }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("New files in these courses download automatically when you sync. iOS decides how often background checks run, usually a few times a day.")
                }
                Section {
                    LabeledContent("Downloaded", value: "\(downloadedCount) files · \(downloadedSize.fileSizeLabel)")
                    Button("Show in Files app", systemImage: "folder") {
                        var comps = URLComponents(url: URL.documentsDirectory, resolvingAgainstBaseURL: false)
                        comps?.scheme = "shareddocuments"
                        if let url = comps?.url { openURL(url) }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Files are saved in Files → On My iPhone → Beep, one folder per course, so any app can open and edit them.")
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

extension Bundle {
    var versionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
