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
    #if os(macOS)
    @Environment(DownloadFolder.self) private var folder
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var pickFolder = false
    #endif

    /// Re-arms (or stops) periodic checks after a settings change.
    private func rescheduleChecks() {
        #if os(iOS)
        backgroundRefresh ? BackgroundRefresh.schedule() : BackgroundRefresh.cancel()
        #else
        MacSyncScheduler.shared?.reschedule()
        #endif
    }

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
                                Text(user.fullname.isEmpty ? String(localized: "Signed in") : user.fullname).font(.headline)
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
                        .onChange(of: backgroundRefresh) { _, _ in rescheduleChecks() }
                    if backgroundRefresh {
                        Picker(selection: $refreshMinutes) {
                            Text("Every hour at most").tag(60.0)
                            Text("Every 2 hours").tag(120.0)
                            Text("Every 6 hours").tag(360.0)
                            Text("Once a day").tag(1440.0)
                        } label: {
                            Label("Check frequency", systemImage: "timer")
                        }
                        .onChange(of: refreshMinutes) { _, _ in rescheduleChecks() }
                        #if os(iOS)
                        Toggle("Background downloads on Wi-Fi only", systemImage: "wifi", isOn: $backgroundWifiOnly)
                        #endif
                    }
                    Toggle("Notify about new files", systemImage: "bell.badge", isOn: $notifications)
                        .onChange(of: notifications) { _, on in
                            if on { Task { notifications = await Notifier.requestPermission() } }
                        }
                } header: {
                    Text("Sync")
                } footer: {
                    #if os(iOS)
                    Text("New files in these courses download automatically when you sync. Background checks are skipped in Low Power Mode; iOS may space them out further than the frequency you pick. Wi-Fi only postpones background downloads until you open the app or reach Wi-Fi.")
                    #else
                    Text("New files in these courses download automatically when you sync. Beep keeps checking from the menu bar while its window is closed, and catches up when your Mac wakes. Checks are skipped in Low Power Mode.")
                    #endif
                }
                Section {
                    NavigationLink {
                        StorageView()
                    } label: {
                        LabeledContent("Downloaded", value: String(localized: "\(downloadedCount) files · \(downloadedSize.fileSizeLabel)"))
                    }
                    #if os(iOS)
                    Button("Show in Files app", systemImage: "folder") {
                        var comps = URLComponents(url: URL.documentsDirectory, resolvingAgainstBaseURL: false)
                        comps?.scheme = "shareddocuments"
                        if let url = comps?.url { openURL(url) }
                    }
                    #else
                    LabeledContent("Download folder") {
                        Text(folder.url?.path(percentEncoded: false).abbreviatingHome ?? String(localized: "Not chosen"))
                            .truncationMode(.middle)
                            .lineLimit(1)
                    }
                    HStack {
                        Button("Choose…") { pickFolder = true }
                        Button("Show in Finder") { folder.showInFinder() }
                            .disabled(!folder.isChosen)
                    }
                    if let error = folder.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    #endif
                } header: {
                    Text("Storage")
                } footer: {
                    #if os(iOS)
                    Text("Files are saved in Files → On My iPhone → Beep, one folder per course, so any app can open and edit them.")
                    #else
                    Text("One folder per course. When you pick a new folder, files already downloaded move there.")
                    #endif
                }
                #if os(macOS)
                Section {
                    Toggle("Open at login", systemImage: "power", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, on in launchAtLogin = LaunchAtLogin.set(on) }
                } footer: {
                    Text("Beep starts with your Mac and keeps your courses up to date from the menu bar.")
                }
                #endif
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
            .inlineNavigationTitle()
            #if os(iOS)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            #else
            .fileImporter(isPresented: $pickFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { folder.choose(url) }
            }
            #endif
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
