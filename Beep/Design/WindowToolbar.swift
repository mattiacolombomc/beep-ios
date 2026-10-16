import SwiftUI

#if os(macOS)
/// What the Mac window's toolbar acts on for one screen: its search text, its file selection and,
/// for a course, the "…" menu's options. The toolbar never adds or removes items: when the
/// visible screen has nothing to search or select, those items stay in place, disabled (HIG:
/// "keep consistent groupings and placement"). Items that came and went with each section made
/// AppKit re-tile the toolbar on every switch.
@Observable
final class ToolbarTarget {
    var search: SearchText?
    var searchPrompt: LocalizedStringResource = "Search"
    var selection: FileSelection?
    var canSelect = false
    var course: CourseViewOptions?
}

/// The screens that offer toolbar targets, per section, in the order they appeared: the last one
/// is on top (a course opened from Search covers the search screen until it is popped).
@Observable
final class WindowToolbarModel {
    private var stacks: [AppRouter.AppTab: [ToolbarTarget]] = [:]

    func top(of tab: AppRouter.AppTab) -> ToolbarTarget? { stacks[tab]?.last }

    func push(_ target: ToolbarTarget, in tab: AppRouter.AppTab) {
        stacks[tab, default: []].removeAll { $0 === target }
        stacks[tab, default: []].append(target)
    }

    func remove(_ target: ToolbarTarget, from tab: AppRouter.AppTab) {
        stacks[tab]?.removeAll { $0 === target }
    }
}

/// Offers a screen's search, selection and course menu to the window toolbar while it is shown.
/// The inputs are references plus one Bool, so the screen's own re-renders do not reach the toolbar.
private struct WindowToolbarRegistration: ViewModifier {
    let search: SearchText?
    let prompt: LocalizedStringResource
    let selection: FileSelection?
    let canSelect: Bool
    let course: CourseViewOptions?
    @State private var target = ToolbarTarget()
    @Environment(\.sectionTab) private var tab
    @Environment(WindowToolbarModel.self) private var model: WindowToolbarModel?

    func body(content: Content) -> some View {
        content
            .onAppear {
                target.search = search
                target.searchPrompt = prompt
                target.selection = selection
                target.course = course
                target.canSelect = canSelect
                if let tab { model?.push(target, in: tab) }
            }
            .onDisappear { if let tab { model?.remove(target, from: tab) } }
            .onChange(of: canSelect) { _, value in target.canSelect = value }
    }
}

extension View {
    func windowToolbar(search: SearchText? = nil, prompt: LocalizedStringResource = "Search",
                       selection: FileSelection? = nil, canSelect: Bool = false,
                       course: CourseViewOptions? = nil) -> some View {
        modifier(WindowToolbarRegistration(search: search, prompt: prompt, selection: selection,
                                           canSelect: canSelect, course: course))
    }
}
#endif
