import SwiftUI

/// Shown when WeBeep rejects the stored token. Local data and downloads are untouched.
struct SessionExpiredView: View {
    let user: AppSession.UserProfile
    @Environment(AppSession.self) private var session
    @State private var showLogin = false

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "person.badge.clock.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(spacing: Theme.Spacing.s) {
                Text("Your WeBeep session expired").font(.title2.weight(.semibold))
                Text("WeBeep stopped accepting Beep's access key for \(user.fullname.isEmpty ? user.username : user.fullname). Sign in again to resume syncing. Downloaded files and your settings are kept.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, Theme.Spacing.l)
            Spacer()
            VStack(spacing: Theme.Spacing.s) {
                Button {
                    showLogin = true
                } label: {
                    Text("Sign in again").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                Button(role: .destructive) {
                    session.signOut()
                } label: {
                    Text("Sign out and forget this account").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.l)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .coverSheet(isPresented: $showLogin) { LoginView() }
    }
}
