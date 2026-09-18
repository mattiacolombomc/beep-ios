import QuickLook
import SwiftUI

/// Presents QuickLook and the share sheet driven by `FileOpener` state.
struct FilePresenters: ViewModifier {
    @Environment(FileOpener.self) private var opener

    func body(content: Content) -> some View {
        @Bindable var opener = opener
        content
            .quickLookPreview($opener.previewURL)
            .sheet(item: Binding(get: { opener.shareURL.map(ShareItem.init) }, set: { opener.shareURL = $0?.url })) { item in
                ShareSheet(url: item.url)
                    .presentationDetents([.medium, .large])
            }
    }
}

private struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
/// macOS: the system share menu, anchored to a small sheet with the file name.
struct ShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Label(url.lastPathComponent, systemImage: "doc")
                .font(.headline)
            HStack {
                Button("Cancel") { dismiss() }
                ShareLink(item: url) { Label("Share…", systemImage: "square.and.arrow.up") }
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
