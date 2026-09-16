import SwiftUI

/// SSO login screen. Shows the WeBeep web login, with a manual-token fallback.
struct LoginView: View {
    @Environment(AppSession.self) private var session
    @State private var passport = LoginFlow.makePassport()
    @State private var progress: Double = 0
    @State private var isValidating = false
    @State private var showManualToken = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                LoginWebView(passport: passport, onToken: handle, onProgress: { progress = $0 })
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
                    .background(Color(.systemBackground))
                }
            }
            .navigationTitle("WeBeep login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Enter token manually", systemImage: "key") { showManualToken = true }
                        Button("Reload", systemImage: "arrow.clockwise") { passport = LoginFlow.makePassport() }
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

    private func handle(_ creds: LoginFlow.Credentials) {
        guard !isValidating else { return }
        isValidating = true
        Task {
            do {
                try await session.signIn(withToken: creds.token)
            } catch {
                errorMessage = String(describing: error)
                isValidating = false
                passport = LoginFlow.makePassport()
            }
        }
    }
}

/// Fallback: paste the "moodle_mobile_app" security key from WeBeep → Preferences → Security keys.
struct ManualTokenSheet: View {
    @Environment(AppSession.self) private var session
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
                        .textInputAutocapitalization(.never)
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
            .navigationBarTitleDisplayMode(.inline)
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
        isValidating = true
        errorMessage = nil
        Task {
            do {
                try await session.signIn(withToken: token)
                dismiss()
            } catch MoodleError.invalidToken {
                errorMessage = String(localized: "WeBeep rejected this token.")
            } catch {
                errorMessage = String(describing: error)
            }
            isValidating = false
        }
    }
}
