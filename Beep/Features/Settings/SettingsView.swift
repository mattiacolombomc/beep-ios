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

    private var manualPeriods: Int { courses.reduce(0) { $0 + ($1.semesterIsManual ? 1 : 0) } }

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
            Form {
                accountSection
                syncSection
                periodsSection
                storageSection
                #if os(macOS)
                Section {
                    Toggle(isOn: $launchAtLogin) {
                        Label {
                            Text("Open at login")
                            Text("Keeps your courses up to date from the menu bar.")
                        } icon: {
                            Image(systemName: "power")
                        }
                    }
                    .onChange(of: launchAtLogin) { _, on in launchAtLogin = LaunchAtLogin.set(on) }
                }
                #endif
                sessionSection
                #if DEBUG
                debugSection
                #endif
                Section("About") {
                    NavigationLink { AcknowledgementsView() } label: { Label("Acknowledgements", systemImage: "heart") }
                    LabeledContent { Text(Bundle.main.versionString) } label: { Label("Version", systemImage: "info.circle") }
                }
                #if os(iOS)
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                        .frame(maxWidth: .infinity)
                }
                #endif
            }
            .formStyle(.grouped)
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

    // MARK: Sections

    /// Who is signed in; on the Mac the sign-out button sits here, where System Settings puts it.
    @ViewBuilder
    private var accountSection: some View {
        if let user = session.user {
            Section {
                HStack(spacing: Theme.Spacing.m - 4) {
                    AsyncImage(url: user.pictureURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.fullname.isEmpty ? String(localized: "Signed in") : user.fullname).font(.headline)
                        Text(user.username).font(.subheadline).foregroundStyle(.secondary)
                    }
                    #if os(macOS)
                    Spacer()
                    Button("Sign out…") { confirmSignOut = true }
                    #endif
                }
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private var syncSection: some View {
        Section("Sync") {
            NavigationLink {
                SyncCoursesView(courses: courses)
            } label: {
                LabeledContent {
                    Text("\(courses.filter(\.syncEnabled).count)")
                } label: {
                    Label("Auto-download courses", systemImage: "arrow.down.circle")
                }
            }
            Toggle(isOn: $backgroundRefresh) {
                Label {
                    Text("Check in the background")
                    #if os(iOS)
                    Text("Skipped in Low Power Mode.")
                    #else
                    Text("Also with the window closed, from the menu bar.")
                    #endif
                } icon: {
                    Image(systemName: "clock.arrow.2.circlepath")
                }
            }
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
                Toggle(isOn: $backgroundWifiOnly) {
                    Label {
                        Text("Background downloads on Wi-Fi only")
                        Text("Otherwise they wait until you open the app.")
                    } icon: {
                        Image(systemName: "wifi")
                    }
                }
                #endif
            }
            Toggle(isOn: $notifications) {
                Label("Notify about new files", systemImage: "bell.badge")
            }
            .onChange(of: notifications) { _, on in
                if on { Task { notifications = await Notifier.requestPermission() } }
            }
        }
    }

    private func resetPeriods() {
        for course in courses where course.semesterIsManual { course.semesterIsManual = false }
        sync.semesters.resolveDue(force: true)
    }

    /// Mac: title and status on the left, the button on the right, as System Settings lays out a
    /// control. iOS: the button is a row of its own, as Settings does.
    private var periodsSection: some View {
        Section {
            #if os(macOS)
            LabeledContent {
                Button("Use the catalogue for all", action: resetPeriods)
                    .disabled(manualPeriods == 0 || sync.semesters.isRunning)
            } label: {
                Label {
                    Text("Course periods")
                    Text(manualPeriods == 0 ? "Every course follows the catalogue." : "Set by hand: \(manualPeriods)")
                } icon: {
                    Image(systemName: "calendar")
                }
            }
            #else
            LabeledContent {
                Text(manualPeriods == 0 ? "From the catalogue" : "Set by hand: \(manualPeriods)")
            } label: {
                Label("Course periods", systemImage: "calendar")
            }
            Button("Use the catalogue for all", systemImage: "calendar.badge.clock", action: resetPeriods)
                .disabled(manualPeriods == 0 || sync.semesters.isRunning)
            #endif
        } header: {
            Text("Semesters")
        } footer: {
            Text("From Politecnico's public course catalogue. A period set by hand from a course's context menu wins.")
        }
    }

    private var storageSection: some View {
        Section {
            NavigationLink {
                StorageView(courses: courses)
            } label: {
                LabeledContent {
                    Text(String(localized: "\(downloadedCount) files · \(downloadedSize.fileSizeLabel)"))
                } label: {
                    Label("Downloaded", systemImage: "internaldrive")
                }
            }
            #if os(iOS)
            Button {
                var comps = URLComponents(url: URL.documentsDirectory, resolvingAgainstBaseURL: false)
                comps?.scheme = "shareddocuments"
                if let url = comps?.url { openURL(url) }
            } label: {
                Label {
                    Text("Show in Files app")
                    Text("Files → On My iPhone → Beep, one folder per course.")
                } icon: {
                    Image(systemName: "folder")
                }
            }
            #else
            LabeledContent {
                HStack(spacing: Theme.Spacing.s) {
                    Button("Choose…") { pickFolder = true }
                    Button("Show in Finder") { folder.showInFinder() }
                        .disabled(!folder.isChosen)
                }
            } label: {
                Label {
                    Text("Download folder")
                    Text(folder.url?.path(percentEncoded: false).abbreviatingHome ?? String(localized: "Not chosen"))
                        .truncationMode(.middle)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "folder")
                }
            }
            if let error = folder.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            #endif
        } header: {
            Text("Storage")
        } footer: {
            #if os(macOS)
            Text("One folder per course. Pick a new folder and the downloads move there.")
            #endif
        }
    }

    private var sessionSection: some View {
        Section {
            #if os(macOS)
            LabeledContent {
                Button {
                    Task { await renewer.renewNow() }
                } label: {
                    if renewer.isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Renew now")
                    }
                }
                .disabled(renewer.isRunning || session.privateToken == nil)
            } label: {
                Label {
                    Text("WeBeep access key")
                    Text(sessionDetail)
                } icon: {
                    Image(systemName: "key")
                }
            }
            #else
            Label {
                Text("WeBeep access key")
                Text(sessionDetail)
            } icon: {
                Image(systemName: "key")
            }
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
            #endif
        } header: {
            Text("Session")
        } footer: {
            Text("Renewed by itself about every 4 weeks. If WeBeep rejects it anyway you get a notification and a quick sign-in.")
        }
    }

    /// "Obtained 20 Oct 2026, 11:37 · Silent renewal enabled", plus the last renewal's outcome.
    private var sessionDetail: String {
        var parts: [String] = []
        if let at = session.tokenIssuedAt { parts.append(String(localized: "Obtained \(at.formatted(date: .abbreviated, time: .shortened))")) }
        parts.append(session.privateToken == nil ? String(localized: "Silent renewal unavailable, sign in again once") : String(localized: "Silent renewal enabled"))
        if let outcome = renewer.lastOutcome { parts.append(outcomeLabel(outcome)) }
        return parts.joined(separator: " · ")
    }

    #if DEBUG
    private var debugSection: some View {
        Section("Debug") {
            Button("Restart onboarding") {
                UserDefaults.standard.set(false, forKey: "onboarding.done")
            }
            Button("Simulate expired session", role: .destructive) {
                Task {
                    if let user = session.user {
                        _ = await sync.syncAll(client: MoodleClient(token: "expired-token"), userID: user.id, trigger: .manual)
                    }
                }
            }
        }
    }
    #endif
}

extension Bundle {
    var versionString: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
