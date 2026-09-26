import QuickLook
import SwiftUI

/// Presents QuickLook and the share sheet driven by `FileOpener` state.
struct FilePresenters: ViewModifier {
    @Environment(FileOpener.self) private var opener

    func body(content: Content) -> some View {
        @Bindable var opener = opener
        #if os(iOS)
        content
            .quickLookPreview($opener.previewURL)
            .sheet(item: Binding(get: { opener.shareURLs.map(ShareItem.init) }, set: { opener.shareURLs = $0?.urls })) { item in
                ShareSheet(urls: item.urls)
                    .presentationDetents([.medium, .large])
            }
        #else
        // Shares requested without an anchor (context menu) pop up from the window content.
        content.background(MacSharePicker(urls: $opener.shareURLs))
        #endif
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
/// macOS: the native sharing picker (AirDrop, Mail, Notes, apps…) as a popover anchored to
/// the view this sits behind. Setting `urls` shows it once and clears the binding.
struct MacSharePicker: NSViewRepresentable {
    @Binding var urls: [URL]?
    /// Called when the picker closes, whether a service was chosen or not.
    var onDismiss: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func updateNSView(_ view: NSView, context: Context) {
        guard let urls, !urls.isEmpty else { return }
        context.coordinator.onDismiss = onDismiss
        DispatchQueue.main.async {
            self.urls = nil
            guard view.window != nil else { return }
            let picker = NSSharingServicePicker(items: urls)
            picker.delegate = context.coordinator
            context.coordinator.picker = picker  // keep it alive while shown
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var onDismiss: (() -> Void)?
        var picker: NSSharingServicePicker?
        init(onDismiss: (() -> Void)?) { self.onDismiss = onDismiss }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            picker = nil
            onDismiss?()
        }
    }
}
#endif

extension View {
    func filePresenters() -> some View { modifier(FilePresenters()) }
}
