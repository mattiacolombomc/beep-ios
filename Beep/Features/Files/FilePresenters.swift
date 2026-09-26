import QuickLook
import SwiftUI

/// Presents QuickLook and the share sheet driven by `FileOpener` state.
struct FilePresenters: ViewModifier {
    @Environment(FileOpener.self) private var opener

    func body(content: Content) -> some View {
        @Bindable var opener = opener
        content
            .quickLookPreview($opener.previewURL)
            .sheet(item: Binding(get: { opener.shareURLs.map(ShareItem.init) }, set: { opener.shareURLs = $0?.urls })) { item in
                ShareSheet(urls: item.urls)
                    .presentationDetents([.medium, .large])
            }
    }
}

private struct ShareItem: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.path).joined(separator: "\n") }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
/// macOS: the system share menu, anchored to a small sheet with the file name(s).
struct ShareSheet: View {
    let urls: [URL]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            if urls.count == 1, let url = urls.first {
                Label(url.lastPathComponent, systemImage: "doc").font(.headline)
            } else {
                Label("\(urls.count) files", systemImage: "doc.on.doc").font(.headline)
            }
            HStack {
                Button("Cancel") { dismiss() }
                ShareLink(items: urls) { Label("Share…", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.Spacing.l)
    }
}
#endif

extension View {
    func filePresenters() -> some View { modifier(FilePresenters()) }
}
