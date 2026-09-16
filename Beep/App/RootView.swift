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
        case .signedIn:
            if onboardingDone || DemoData.isEnabled {
                MainTabs()
            } else {
                OnboardingFlow()
            }
        }
    }
}
