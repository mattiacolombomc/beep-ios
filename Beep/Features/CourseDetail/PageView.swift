import SwiftUI
import WebKit

/// Moodle "page" module: render its index.html (token-authenticated) in a web view.
struct PageView: View {
    let module: CourseModule
    @Environment(\.openURL) private var openURL

    private var indexURL: URL? {
        module.files.first { $0.filename.lowercased().hasSuffix(".html") }.flatMap { URL(string: $0.remoteURL) }
            ?? module.url.flatMap(URL.init(string:))
    }

    var body: some View {
        Group {
            if let indexURL {
                WebView(url: indexURL)
            } else {
                ContentUnavailableView("Nothing to show", systemImage: "doc.richtext")
            }
        }
        .navigationTitle(module.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let s = module.url, let url = URL(string: s) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Open on WeBeep", systemImage: "safari") { openURL(url) }
                }
            }
        }
    }
}
