import SwiftUI

extension EnvironmentValues {
    /// The Mac section a view belongs to (constant for its whole life; nil on iOS). A changing
    /// "is active" environment value made every List of every section update on each switch: the
    /// Lists are AppKit views that refresh on any environment change.
    @Entry var sectionTab: AppRouter.AppTab? = nil
}

/// Whether the view's Mac section is the visible one. Reads the router directly, so only the
/// small toolbar and focus modifiers that use it update when the section changes. Always true on
/// iOS, where TabView shows one tab's toolbar by itself.
@propertyWrapper
struct ActiveSection: DynamicProperty {
    @Environment(\.sectionTab) private var tab
    @Environment(AppRouter.self) private var router: AppRouter?

    init() {}

    var wrappedValue: Bool {
        guard let tab, let router else { return true }
        return router.selectedTab == tab
    }
}

/// "Select" / "Done" for screens with multi-select. Inputs are the selection object and one
/// Bool, so the host's frequent re-renders (typing, sync updates) do not re-emit the toolbar.
struct SelectionToolbar: ViewModifier {
    let selection: FileSelection
    /// Whether there is anything to select.
    let canSelect: Bool
    /// Hide "Select" instead of disabling it when there is nothing to select.
    var hidesWhenEmpty = false
    @ActiveSection private var isActive

    func body(content: Content) -> some View {
        content.toolbar {
            if isActive {
                ToolbarItem(placement: .trailingBar) {
                    if selection.isActive {
                        Button("Done") { selection.end() }
                    } else if canSelect || !hidesWhenEmpty {
                        Button("Select") { selection.begin() }.disabled(!canSelect)
                    }
                }
            }
        }
    }
}

/// A section's navigation title. On the Mac the window sets the title itself (`WindowTitle`):
/// with every section mounted, titles from hidden sections would compete for the toolbar.
struct SectionTitle: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content.navigationTitle(title)
        #endif
    }
}

extension View {
    func sectionTitle(_ title: LocalizedStringResource) -> some View {
        modifier(SectionTitle(title: String(localized: title)))
    }
    func sectionTitle(verbatim title: String) -> some View {
        modifier(SectionTitle(title: title))
    }
}
