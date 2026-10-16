import SwiftData
import SwiftUI

/// The main window's toolbar. Its items are the same in every section and never come or go:
/// what a section cannot use is disabled in place (HIG: "keep consistent groupings and
/// placement"). Each item reads only what it shows, so a section switch updates a few small
/// views instead of making AppKit re-tile the toolbar. Search, Select and "…" act on the screen
/// on top of the visible section (`WindowToolbarModel`).
struct MainToolbar: ToolbarContent {
    let courses: CourseSelection

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { SidebarButton(courses: courses) }
        ToolbarItem(placement: .navigation) { FilterSlot() }
        ToolbarItem(placement: .principal) { SectionPicker() }
        ToolbarItem(placement: .primaryAction) { SearchSlot() }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) { SelectSlot() }
        ToolbarItem(placement: .primaryAction) { CourseMenuSlot() }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) { NotificationsButton() }
        ToolbarItem(placement: .primaryAction) { SettingsButton() }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) { SyncButton() }
    }
}

/// The screen the toolbar acts on: the top of the visible section's stack.
@propertyWrapper
private struct ActiveTarget: DynamicProperty {
    @Environment(AppRouter.self) private var router
    @Environment(WindowToolbarModel.self) private var model
    init() {}
    var wrappedValue: ToolbarTarget? { model.top(of: router.selectedTab) }
}

/// Only the picker and the layers read `selectedTab`: a switch re-renders them, not the window.
private struct SectionPicker: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        @Bindable var router = router
        Picker("Section", selection: $router.selectedTab) {
            Label("Courses", systemImage: "graduationcap").tag(AppRouter.AppTab.courses)
            Label("Recent", systemImage: "clock").tag(AppRouter.AppTab.recent)
            Label("Activity", systemImage: "arrow.down.circle").tag(AppRouter.AppTab.activity)
            Label("Search", systemImage: "magnifyingglass").tag(AppRouter.AppTab.search)
        }
        .pickerStyle(.segmented)
        .labelStyle(.titleAndIcon)
    }
}

/// Shows or hides the course list. The split view's own toggle is removed: it belonged to the
/// Courses section and left the toolbar with the section.
private struct SidebarButton: View {
    let courses: CourseSelection
    @Environment(AppRouter.self) private var router
    var body: some View {
        Button("Course List", systemImage: "sidebar.left") {
            withAnimation { courses.columns = courses.columns == .detailOnly ? .all : .detailOnly }
        }
        .help("Show or hide the course list")
        .disabled(router.selectedTab != .courses)
    }
}

/// The course list's filters; they only apply to the Courses section.
private struct FilterSlot: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        CoursesFilterMenu { router.showCatalog = true }
            .disabled(router.selectedTab != .courses)
    }
}

private struct SearchSlot: View {
    @ActiveTarget private var target
    var body: some View {
        ToolbarSearchField(search: target?.search, prompt: String(localized: target?.searchPrompt ?? "Search"))
    }
}

/// "Select" / "Done" for the visible screen's files.
private struct SelectSlot: View {
    @ActiveTarget private var target
    var body: some View {
        let selection = target?.selection
        let active = selection?.isActive ?? false
        Button(active ? "Done" : "Select") {
            if active { selection?.end() } else { selection?.begin() }
        }
        .disabled(selection == nil || !(active || target?.canSelect == true))
    }
}

/// The open course's "…" menu, disabled when no course is on screen.
private struct CourseMenuSlot: View {
    @ActiveTarget private var target
    @Environment(FileOpener.self) private var opener
    var body: some View {
        CourseMenuButton(options: target?.course, selection: target?.selection, opener: opener)
            .frame(width: 28, height: 22)
            .help("More")
            // Not `isEnabled` on the NSButton: SwiftUI sets it from the environment on each update.
            .disabled(target?.course == nil)
    }
}

private struct NotificationsButton: View {
    @Environment(AppRouter.self) private var router
    @Query(filter: #Predicate<WebeepNotification> { !$0.read }) private var unread: [WebeepNotification]
    var body: some View {
        Button("Notifications", systemImage: "bell") { router.showNotifications = true }
            .badge(unread.count)
    }
}

private struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button("Settings", systemImage: "gearshape") { openSettings() }
    }
}
