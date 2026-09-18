import SwiftUI

/// First screen for signed-out users.
struct WelcomeView: View {
    @State private var showLogin = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "graduationcap.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.bottom, 24)
            Text("Beep")
                .font(.largeTitle.bold())
            Text("Your WeBeep files, always in sync.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                FeatureLine(symbol: "arrow.triangle.2.circlepath", title: "Sync", text: "New material downloads itself for the courses you pick.")
                FeatureLine(symbol: "sparkles", title: "What's new", text: "See at a glance which files appeared since your last visit.")
                FeatureLine(symbol: "magnifyingglass", title: "Find anything", text: "Search files inside a course or across all of them.")
                FeatureLine(symbol: "folder", title: "Open anywhere", text: "Files live in the Files app, ready for GoodNotes, Notability or anything else.")
            }
            .padding(.horizontal, 32)
            Spacer()
            Button {
                showLogin = true
            } label: {
                Text("Sign in with Polimi account")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            Text("Not affiliated with Politecnico di Milano.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(Color.appBackground)
        .coverSheet(isPresented: $showLogin) { LoginView() }
    }
}

private struct FeatureLine: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    WelcomeView().environment(AppSession())
}
