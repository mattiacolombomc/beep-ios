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
    @AppStorage("settings.refreshMinutes") private var refreshMinutes = 120.0
    @AppStorage("settings.backgroundWifiOnly") private var backgroundWifiOnly = false
    @Environment(TokenRenewer.self) private var renewer
    @Environment(SyncEngine.self) private var sync

    private func outcomeLabel(_ o: TokenRenewer.Outcome) -> String {
        switch o {
        case .renewed: String(localized: "Renewed just now")
        case .notNeeded: String(localized: "Not needed yet")
        case .unavailable(let why): String(localized: "Unavailable: \(why)")
        case .failed(let why): String(localized: "Failed: \(why)")
        }
    }

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
                    if backgroundRefresh {
                        Picker(selection: $refreshMinutes) {
                            Text("Every hour at most").tag(60.0)
                            Text("Every 2 hours").tag(120.0)
                            Text("Every 6 hours").tag(360.0)
                            Text("Once a day").tag(1440.0)
                        } label: {
                            Label("Check frequency", systemImage: "timer")
                        }
                        .onChange(of: refreshMinutes) { _, _ in BackgroundRefresh.schedule() }
                        Toggle("Background downloads on Wi-Fi only", systemImage: "wifi", isOn: $backgroundWifiOnly)
                    }
                    Toggle("Notify about new files", systemImage: "bell.badge", isOn: $notifications)
                        .onChange(of: notifications) { _, on in
                            if on { Task { notifications = await Notifier.requestPermission() } }
                        }
                } header: {
                    Text("Sync")
                } footer: {
                    Text("New files in these courses download automatically when you sync. Background checks are skipped in Low Power Mode; iOS may space them out further than the frequency you pick. Wi-Fi only postpones background downloads until you open the app or reach Wi-Fi.")
                }
                Section {
                    NavigationLink {
                        StorageView()
                    } label: {
                        LabeledContent("Downloaded", value: String(localized: "\(downloadedCount) files · \(downloadedSize.fileSizeLabel)"))
                    }
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
                Section {
                    LabeledContent("Access key obtained", value: session.tokenIssuedAt?.formatted(date: .abbreviated, time: .shortened) ?? "—")
                    LabeledContent("Silent renewal", value: session.privateToken == nil ? String(localized: "Unavailable, sign in again once") : String(localized: "Enabled"))
                    Button {
                        Task { await renewer.renewNow() }
                    } label: {
                        HStack {
                            Label("Renew access key now", systemImage: "key.viewfinder")
                            Spacer()
                            if renewer.isRunning { ProgressView().controlSize(.small) }
                        }
                    }
                    .disabled(renewer.isRunning || session.privateToken == nil)
                    if let outcome = renewer.lastOutcome {
                        Text(outcomeLabel(outcome)).font(.footnote).foregroundStyle(.secondary)
                    }
                    #if DEBUG
                    Button("Restart onboarding (debug)") {
                        UserDefaults.standard.set(false, forKey: "onboarding.done")
                    }
                    Button("Simulate expired session (debug)", role: .destructive) {
                        Task {
                            if let user = session.user, let sync = Optional(sync) {
                                _ = await sync.syncAll(client: MoodleClient(token: "expired-token"), userID: user.id, trigger: .manual)
                            }
                        }
                    }
                    #endif
                } header: {
                    Text("Session")
                } footer: {
                    Text("Beep renews the WeBeep access key by itself about every 4 weeks, before it can expire. If WeBeep rejects it anyway you get a notification and a quick sign-in.")
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
