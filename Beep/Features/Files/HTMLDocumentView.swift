import SwiftUI
import WebKit

/// Moodle HTML (notifications, forum posts) with system typography and automatic dark mode,
/// rendered by WebKit. The `WebPage` is a model object independent of any view: build it as
/// soon as the content is known and the detail shows rendered text the moment it is pushed,
/// instead of a blank web view that fills in a second later.
@MainActor
enum HTMLDocument {
    typealias Section = (heading: String, meta: String, html: String)

    /// A page already loading the styled document; taps on links leave the app.
    static func page(title: String?, meta: String?, bodyHTML: String, extraSections: [Section] = []) -> WebPage {
        var config = WebPage.Configuration()
        #if os(iOS)
        config.dataDetectorTypes = [.link, .phoneNumber]
        #endif
        let page = WebPage(configuration: config, navigationDecider: LinkOpener())
        _ = page.load(html: html(title: title, meta: meta, bodyHTML: bodyHTML, extraSections: extraSections), baseURL: WeBeep.host)
        return page
    }

    static func html(title: String?, meta: String?, bodyHTML: String, extraSections: [Section] = []) -> String {
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

    /// Links open in the browser; the document's own load (and detected links' previews) go through.
    private struct LinkOpener: WebPage.NavigationDeciding {
        func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
            if action.navigationType == .linkActivated, let url = action.request.url {
                Platform.open(url)
                return .cancel
            }
            return .allow
        }
    }
}

/// A prepared `HTMLDocument` page over the system background.
struct HTMLDocumentView: View {
    let page: WebPage

    var body: some View {
        WebView(page)
            .webViewContentBackground(.hidden)
    }
}
