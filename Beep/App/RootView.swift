import SwiftData
import SwiftUI

/// Auth gate: welcome/login when signed out, onboarding after the first login, then the main tabs.
struct RootView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("onboarding.done") private var onboardingDone = false
    @Environment(FileOpener.self) private var opener
    @Environment(\.modelContext) private var context
    /// Set when the layout migration moved files; cleared once the user has read the notice.
    @AppStorage("files.layout2.notice") private var layoutNoticePending = false

    var body: some View {
        content
            .preferredColorScheme(Self.forcedScheme)
            .task {
                guard !DemoData.isEnabled else { return }
                if opener.migrateLayout(context: context) > 0 { layoutNoticePending = true }
            }
            .alert("Your files were reorganised", isPresented: $layoutNoticePending) {
                #if os(macOS)
                Button("Show in Finder") { opener.openDownloadRoot() }
                #else
                Button("Show in Files app") { opener.openDownloadRoot() }
                #endif
                Button("OK", role: .cancel) {}
            } message: {
                Text("Downloads now live in one folder per course, with a sub-folder for each academic year (and professor, when a course has two sections in the same year). Nothing was deleted.")
            }
    }

    /// Debug: `-forceDark` / `-forceLight` override the system appearance for screenshots and checks.
    private static var forcedScheme: ColorScheme? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-forceDark") { return .dark }
        if args.contains("-forceLight") { return .light }
        #endif
        return nil
    }

    @ViewBuilder
    private var content: some View {
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
