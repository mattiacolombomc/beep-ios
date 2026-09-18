import SwiftUI
import WebKit

/// Renders Moodle HTML (notifications, forum posts, labels) in a WKWebView with
/// system typography and automatic dark mode. Links open in the browser.
struct HTMLDocumentView: PlatformViewRepresentable {
    let title: String?
    let meta: String?
    let bodyHTML: String
    var extraSections: [(heading: String, meta: String, html: String)] = []

    func makeCoordinator() -> Coordinator { Coordinator() }

    #if os(iOS)
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.link, .phoneNumber]
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(document, baseURL: WeBeep.host)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
    #else
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.setValue(false, forKey: "drawsBackground")   // let the window background show through
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(document, baseURL: WeBeep.host)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif

    private var document: String {
        var parts: [String] = []
        if let title { parts.append("<h1>\(title)</h1>") }
        if let meta { parts.append("<p class=meta>\(meta)</p>") }
        parts.append("<div class=content>\(bodyHTML)</div>")
        for s in extraSections {
            parts.append("<hr><h3>\(s.heading)</h3><p class=meta>\(s.meta)</p><div class=content>\(s.html)</div>")
        }
        return """
        <!doctype html><html><head><meta charset=utf-8>
        <meta name=viewport content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name=color-scheme content="light dark">
        <style>
        :root { color-scheme: light dark; }
        body { font: -apple-system-body; font-family: -apple-system, system-ui; margin: 16px; color: -apple-system-label; background: transparent; line-height: 1.4; word-wrap: break-word; }
        h1 { font: -apple-system-title2; font-weight: 700; margin: 0 0 6px; }
        h3 { font: -apple-system-headline; margin: 12px 0 2px; }
        .meta { color: -apple-system-secondary-label; font: -apple-system-subheadline; margin: 0 0 12px; }
        img, video, iframe { max-width: 100%; height: auto; border-radius: 8px; }
        table { border-collapse: collapse; width: 100%; font-size: 0.95em; } td, th { border: 1px solid -apple-system-separator; padding: 4px 6px; }
        a { color: -apple-system-blue; }
        blockquote { border-left: 3px solid -apple-system-separator; margin: 0; padding-left: 12px; color: -apple-system-secondary-label; }
        pre { overflow-x: auto; padding: 8px; background: -apple-system-secondary-background; border-radius: 8px; }
        hr { border: 0; border-top: 1px solid -apple-system-separator; margin: 20px 0; }
        </style></head><body>\(parts.joined())</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                Platform.open(url)
                return .cancel
            }
            return .allow
        }
    }
}
