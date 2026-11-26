import SwiftUI
import WebKit

/// Drives the WeBeep SSO in a web view and intercepts the mobile-token callback.
/// Flow: shibboleth login → lands on /my/ → we load launch.php → Moodle redirects to
/// moodlemobile://token=… which WebKit refuses to open; we catch it in the policy delegate.
struct LoginWebView: PlatformViewRepresentable {
    let passport: String
    /// iPhone and iPad only: ask CIE, or every other provider, for the desktop page (see `LoginSite`).
    var cieDesktop = LoginSite.cieDesktopDefault
    var spidDesktop = LoginSite.spidDesktopDefault
    let onToken: (LoginFlow.Credentials) -> Void
    let onProgress: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.apply(cieDesktop: cieDesktop, spidDesktop: spidDesktop, to: uiView)
    }
    #else
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif

    private func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        #if os(iOS)
        config.userContentController.addUserScript(
            WKUserScript(source: LoginSite.viewportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        #endif
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.isInspectable = true
        coordinator.observe(webView)
        webView.load(URLRequest(url: WeBeep.shibbolethLogin))
        return webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let parent: LoginWebView
        private var observation: NSKeyValueObservation?
        private var launched = false
        private var cieDesktop: Bool
        private var spidDesktop: Bool

        init(_ parent: LoginWebView) {
            self.parent = parent
            cieDesktop = parent.cieDesktop
            spidDesktop = parent.spidDesktop
        }

        #if os(iOS)
        /// A changed setting reloads the page on screen, when it is one the setting applies to.
        func apply(cieDesktop: Bool, spidDesktop: Bool, to webView: WKWebView) {
            guard cieDesktop != self.cieDesktop || spidDesktop != self.spidDesktop else { return }
            let before = webView.url.flatMap { LoginSite.wantsDesktop($0, cie: self.cieDesktop, spid: self.spidDesktop) }
            self.cieDesktop = cieDesktop
            self.spidDesktop = spidDesktop
            let after = webView.url.flatMap { LoginSite.wantsDesktop($0, cie: cieDesktop, spid: spidDesktop) }
            if before != after { webView.reload() }
        }
        #endif

        func observe(_ webView: WKWebView) {
            observation = webView.observe(\.estimatedProgress, options: [.new]) { [parent] _, change in
                let value = change.newValue ?? 0
                Task { @MainActor in parent.onProgress(value) }
            }
        }

        func webView(
            _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences
        ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
            guard let url = navigationAction.request.url else { return (.allow, preferences) }
            if let creds = LoginFlow.parseCallback(url, passport: parent.passport) {
                parent.onToken(creds)
                return (.cancel, preferences)
            }
            #if os(iOS)
            if navigationAction.targetFrame?.isMainFrame != false {
                let desktop = LoginSite.wantsDesktop(url, cie: cieDesktop, spid: spidDesktop)
                if let desktop { preferences.preferredContentMode = desktop ? .desktop : .mobile }
                // On iPad the phone version must also say it is an iPhone.
                let asPhone = desktop == false && UIDevice.current.userInterfaceIdiom == .pad
                webView.customUserAgent = asPhone ? LoginSite.phoneUserAgent : nil
            }
            #endif
            return (.allow, preferences)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }
            // Logged in: kick off the token handshake once.
            if !launched, url.host() == WeBeep.host.host(), url.path().hasPrefix("/my") {
                launched = true
                webView.load(URLRequest(url: LoginFlow.launchURL(passport: parent.passport)))
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // The moodlemobile:// redirect surfaces here on some WebKit versions; the URL is in the error.
            if let url = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL,
               let creds = LoginFlow.parseCallback(url, passport: parent.passport) {
                parent.onToken(creds)
            }
        }
    }
}
