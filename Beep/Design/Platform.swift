import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

#if os(iOS)
typealias PlatformViewRepresentable = UIViewRepresentable
#else
typealias PlatformViewRepresentable = NSViewRepresentable
#endif

/// Small bridges so feature views compile unchanged on iOS and macOS.
/// Each one maps an iOS-only idiom to its natural macOS counterpart.
extension View {
    /// Inline navigation title on iOS; macOS windows have no large titles.
    @ViewBuilder func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Large navigation title on iOS; no-op on macOS.
    @ViewBuilder func largeNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// Settings-style grouped list: inset grouped on iOS, inset on macOS.
    @ViewBuilder func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    /// Search field that collapses into a toolbar button on iOS; macOS keeps its standard field.
    @ViewBuilder func minimizedSearchToolbar() -> some View {
        #if os(iOS)
        searchToolbarBehavior(.minimize)
        #else
        self
        #endif
    }

    /// Full-screen cover on iOS; a sheet sized like a login window on macOS.
    @ViewBuilder func coverSheet<Cover: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Cover) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented) { content().frame(minWidth: 520, idealWidth: 620, minHeight: 620, idealHeight: 720) }
        #endif
    }

    /// Text field for codes and tokens: no autocapitalisation or autocorrection.
    @ViewBuilder func plainTextInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Trailing navigation-bar slot on iOS, primary toolbar slot on macOS.
    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}

enum Platform {
    /// Opens a web link in the default browser.
    @MainActor static func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    /// Shows a downloaded file in Files (iOS) or selects it in Finder (macOS).
    @MainActor static func reveal(_ fileURL: URL) {
        #if os(iOS)
        var comps = URLComponents(url: fileURL.deletingLastPathComponent(), resolvingAgainstBaseURL: false)
        comps?.scheme = "shareddocuments"
        if let target = comps?.url { UIApplication.shared.open(target) }
        #else
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        #endif
    }

    /// Puts plain text on the system clipboard.
    @MainActor static func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Opens a folder in Files (iOS) or Finder (macOS).
    @MainActor static func openFolder(_ folder: URL) {
        #if os(iOS)
        var comps = URLComponents(url: folder, resolvingAgainstBaseURL: false)
        comps?.scheme = "shareddocuments"
        if let target = comps?.url { UIApplication.shared.open(target) }
        #else
        NSWorkspace.shared.open(folder)
        #endif
    }
}

/// System background colours with a matching macOS counterpart.
extension Color {
    static var appBackground: Color {
        #if os(iOS)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var secondaryBackground: Color {
        #if os(iOS)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    static var cardBackground: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        // The sidebar is already light: a neutral tint separates the card in both appearances.
        Color.primary.opacity(0.07)
        #endif
    }
}

#if os(macOS)
import AppKit

/// Native search field for a sidebar column. On macOS `.searchable` is part of the window
/// toolbar: typing re-emitted the toolbar of the view owning the text (the bar flashed, open
/// menus closed; 219 ms per keystroke). A plain NSSearchField filters without touching it.
struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSSearchField { text.wrappedValue = field.stringValue }
        }
    }
}

/// Native NSSearchField for the window toolbar, used instead of `.searchable` on the Mac: with
/// `.searchable`, typing re-emitted the toolbar of the view owning the text and AppKit re-tiled it.
struct ToolbarSearchField: NSViewRepresentable {
    let search: SearchText
    let prompt: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        field.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != search.text { field.stringValue = search.text }
        if context.coordinator.handledFocus != search.focusRequest {
            context.coordinator.handledFocus = search.focusRequest
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(search: search) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let search: SearchText
        var handledFocus = 0
        init(search: SearchText) { self.search = search }
        func controlTextDidChange(_ note: Notification) {
            if let field = note.object as? NSSearchField { search.text = field.stringValue }
        }
    }
}

/// Puts a `ToolbarSearchField` in the toolbar. Its only input is the `SearchText` object, so
/// the host's re-renders (results arriving, every keystroke) do not re-emit this toolbar item.
struct ToolbarSearch: ViewModifier {
    let search: SearchText
    let prompt: LocalizedStringResource
    @ActiveSection private var isActive

    @ViewBuilder func body(content: Content) -> some View {
        toolbar(content)
    }

    private func toolbar(_ content: Content) -> some View {
        content.toolbar {
            if isActive {
                ToolbarItem(placement: .primaryAction) {
                    ToolbarSearchField(search: search, prompt: String(localized: prompt))
                }
            }
        }
    }
}
#endif

/// Text of a search field. A reference type on purpose: views and toolbar modifiers hold the
/// same object across renders, so typing never changes their inputs (see `ToolbarSearch`).
@Observable
final class SearchText {
    var text = ""
    /// Bumped to move the cursor into the field (Mac toolbar field).
    var focusRequest = 0
}
