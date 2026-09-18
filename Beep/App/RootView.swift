import SwiftUI

/// Auth gate: welcome/login when signed out, onboarding after the first login, then the main tabs.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("onboarding.done") private var onboardingDone = false

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
        case .signedOut:
            WelcomeView()
        case .expired(let user):
            SessionExpiredView(user: user)
        case .signedIn:
            if onboardingDone || (DemoData.isEnabled && !Self.previewOnboarding) {
                #if os(iOS)
                MainTabs()
                #else
                MacMainView()
                #endif
            } else {
                OnboardingFlow()
            }
        }
    }

    /// Debug: `-demo -previewOnboarding` walks the onboarding on sample data.
    private static var previewOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-previewOnboarding")
        #else
        false
        #endif
    }
}
