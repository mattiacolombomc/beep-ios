import SwiftUI

/// Auth gate: welcome/login when signed out, the main tabs when signed in.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
        case .signedOut:
            WelcomeView()
        case .signedIn:
            MainTabs()
        }
    }
}
