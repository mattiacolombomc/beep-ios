import SwiftUI

extension EnvironmentValues {
    /// False for a Mac section that stays mounted behind the visible one (see `MacMainView`).
    /// Only toolbar and title modifiers read it, so a switch never re-renders a section's content.
    /// Always true on iOS, where TabView shows one tab's toolbar by itself.
    @Entry var isActiveSection: Bool = true
}

/// "Select" / "Done" for screens with multi-select. Inputs are the selection object and one
/// Bool, so the host's frequent re-renders (typing, sync updates) do not re-emit the toolbar.
struct SelectionToolbar: ViewModifier {
    let selection: FileSelection
    /// Whether there is anything to select.
    let canSelect: Bool
    /// Hide "Select" instead of disabling it when there is nothing to select.
    var hidesWhenEmpty = false
    @Environment(\.isActiveSection) private var isActive

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
