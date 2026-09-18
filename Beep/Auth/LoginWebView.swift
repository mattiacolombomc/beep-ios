import SwiftUI
import WebKit

/// Drives the WeBeep SSO in a web view and intercepts the mobile-token callback.
/// Flow: shibboleth login → lands on /my/ → we load launch.php → Moodle redirects to
/// moodlemobile://token=… which WebKit refuses to open; we catch it in the policy delegate.
struct LoginWebView: PlatformViewRepresentable {
    let passport: String
    let onToken: (LoginFlow.Credentials) -> Void
    let onProgress: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #else
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif

    private func makeWebView(_ coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
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

        init(_ parent: LoginWebView) { self.parent = parent }

        func observe(_ webView: WKWebView) {
            observation = webView.observe(\.estimatedProgress, options: [.new]) { [parent] _, change in
                let value = change.newValue ?? 0
                Task { @MainActor in parent.onProgress(value) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            if let creds = LoginFlow.parseCallback(url, passport: parent.passport) {
                parent.onToken(creds)
                return .cancel
            }
            return .allow
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
