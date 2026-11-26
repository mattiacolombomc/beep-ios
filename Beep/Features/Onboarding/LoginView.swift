import SwiftUI

/// SSO login screen. Shows the WeBeep web login, with a manual-token fallback.
struct LoginView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var passport = LoginFlow.makePassport()
    @State private var progress: Double = 0
    @State private var isValidating = false
    @State private var showManualToken = false
    @State private var errorMessage: String?
    #if os(iOS)
    @AppStorage(LoginSite.cieDesktopKey) private var cieDesktop = LoginSite.cieDesktopDefault
    @AppStorage(LoginSite.spidDesktopKey) private var spidDesktop = LoginSite.spidDesktopDefault
    #endif

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                webView
                    .id(passport) // a new passport is a new attempt: start again from the first page
                    .ignoresSafeArea(edges: .bottom)
                if progress < 1 {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }
                if isValidating {
                    ContentUnavailableView {
                        ProgressView()
                    } description: {
                        Text("Signing you in…")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
                }
            }
            .navigationTitle("WeBeep login")
            .inlineNavigationTitle()
            .toolbar {
                // The login covers the whole screen (iOS) or is a sheet (macOS): without this there is no way out
                // of a provider's error page.
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: Self.menuPlacement) {
                    Menu {
                        Button("Enter token manually", systemImage: "key") { showManualToken = true }
                        Button("Reload", systemImage: "arrow.clockwise") { passport = LoginFlow.makePassport() }
                        #if os(iOS)
                        Section("Desktop site") {
                            Toggle("CIE", isOn: $cieDesktop)
                            Toggle("SPID", isOn: $spidDesktop)
                        }
                        #endif
                    } label: {
                        Label("More", systemImage: "ellipsis")
                    }
                }
            }
            .sheet(isPresented: $showManualToken) {
                ManualTokenSheet()
                    .presentationDetents([.medium, .large])
            }
            .alert("Login failed", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    /// A macOS sheet shows only its cancel and confirm slots: an item in the window's primary slot never appears.
    private static var menuPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .confirmationAction
        #endif
    }

    private var webView: LoginWebView {
        #if os(iOS)
        LoginWebView(passport: passport, cieDesktop: cieDesktop, spidDesktop: spidDesktop, onToken: handle, onProgress: { progress = $0 })
        #else
        LoginWebView(passport: passport, onToken: handle, onProgress: { progress = $0 })
        #endif
    }

    private func handle(_ creds: LoginFlow.Credentials) {
        guard !isValidating else { return }
        isValidating = true
        Task {
            do {
                try await session.signIn(withToken: creds.token, privateToken: creds.privateToken)
                // Normally the screen that opened the login goes away once signed in and takes this with it.
                // Closing here as well keeps the login from staying open when that screen remains.
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isValidating = false
                passport = LoginFlow.makePassport()
            }
        }
    }
}

/// Fallback: paste the "moodle_mobile_app" security key from WeBeep → Preferences → Security keys.
struct ManualTokenSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var token = ""
    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Token", text: $token, axis: .vertical)
                        .lineLimit(3...5)
                        .font(.system(.body, design: .monospaced))
                        .plainTextInput()
                        .autocorrectionDisabled()
                } header: {
                    Text("Mobile web service token")
                } footer: {
                    Text("On WeBeep open Preferences → Security keys and copy the key for the *moodle_mobile_app* service.")
                }
                Section {
                    Button("Open WeBeep security keys", systemImage: "safari") { openURL(WeBeep.securityKeysPage) }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Enter token")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sign in") { submit() }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
                }
            }
        }
    }

    private func submit() {
        if token.trimmingCharacters(in: .whitespacesAndNewlines) == DemoData.reviewPassword {
            do { try DemoData.enter(session: session, context: modelContext); dismiss() } catch { errorMessage = error.localizedDescription }
            return
        }
        isValidating = true
        errorMessage = nil
        Task {
            do {
                try await session.signIn(withToken: token)
                dismiss()
            } catch MoodleError.invalidToken {
                errorMessage = String(localized: "WeBeep rejected this token.")
            } catch {
                errorMessage = error.localizedDescription
            }
            isValidating = false
        }
    }
}
