import AppKit
import SwiftUI

/// The course screen's "…" button on the Mac. Its menu is an NSMenu built when it opens, from
/// the current course and view options, the way AppKit apps build menus: nothing in the toolbar
/// depends on the open course, so opening another course does not rebuild the toolbar (a
/// SwiftUI Menu re-emitted its whole content on every course, ~70 ms).
struct CourseMenuButton: NSViewRepresentable {
    let options: CourseViewOptions?
    let selection: FileSelection?
    let opener: FileOpener

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: String(localized: "More"))!,
                              target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.toolTip = String(localized: "More")
        context.coordinator.update(options: options, selection: selection, opener: opener)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.update(options: options, selection: selection, opener: opener)
        // A borderless symbol button does not dim itself when disabled (no course on screen).
        button.contentTintColor = context.environment.isEnabled ? nil : .tertiaryLabelColor
        button.image = NSImage(systemSymbolName: options?.isCustomized == true ? "ellipsis.circle.fill" : "ellipsis.circle",
                               accessibilityDescription: String(localized: "More"))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator: NSObject {
        private var options: CourseViewOptions?
        private var selection: FileSelection?
        private var opener: FileOpener?
        private var actions: [() -> Void] = []

        func update(options: CourseViewOptions?, selection: FileSelection?, opener: FileOpener) {
            self.options = options
            self.selection = selection
            self.opener = opener
        }

        @objc func open(_ sender: NSButton) {
            guard let options, let course = options.course, let selection, let opener else { return }
            actions.removeAll()
            let menu = NSMenu()
            func item(_ title: LocalizedStringResource, _ symbol: String?, checked: Bool = false, enabled: Bool = true, _ action: @escaping () -> Void) -> NSMenuItem {
                let i = NSMenuItem(title: String(localized: title), action: #selector(run(_:)), keyEquivalent: "")
                i.target = self
                i.tag = actions.count
                i.state = checked ? .on : .off
                i.isEnabled = enabled
                if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
                actions.append(action)
                return i
            }
            menu.autoenablesItems = false
            menu.addItem(item("Select", "checkmark.circle", enabled: !course.files.isEmpty) { selection.begin() })
            menu.addItem(.separator())
            let sort = NSMenuItem(title: String(localized: "Sort"), action: nil, keyEquivalent: "")
            let sortMenu = NSMenu()
            for (value, title) in [(FileSort.position, LocalizedStringResource("Course order")),
                                   (.newest, "Newest first"), (.name, "Name")] {
                sortMenu.addItem(item(title, nil, checked: options.sort == value) { options.sort = value })
            }
            sort.submenu = sortMenu
            menu.addItem(sort)
            menu.addItem(item("Only new files", "sparkles", checked: options.onlyNew) { options.onlyNew.toggle() })
            if options.isCustomized {
                menu.addItem(item("Reset view", "arrow.uturn.backward") { options.sort = .position; options.onlyNew = false })
            }
            menu.addItem(.separator())
            menu.addItem(item("Favourite", "star", checked: course.isFavourite) { course.isFavourite.toggle() })
            menu.addItem(item("Auto-download new files", "arrow.down.circle", checked: course.syncEnabled) { course.syncEnabled.toggle() })
            if let dir = opener.directory(of: course) {
                menu.addItem(item("Show in Finder", "folder") { opener.reveal(dir) })
            }
            menu.addItem(item("Rename folder…", "folder.badge.gearshape") { options.renameTarget = course })
            if course.isArchived {
                menu.addItem(item("Unarchive", "tray.and.arrow.up") { course.isArchived = false })
            }
            menu.addItem(.separator())
            let id = course.id
            menu.addItem(item("Open on WeBeep", "safari") {
                NSWorkspace.shared.open(WeBeep.host.appending(path: "course/view.php").appending(queryItems: [URLQueryItem(name: "id", value: String(id))]))
            })
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        }

        @objc private func run(_ sender: NSMenuItem) {
            guard actions.indices.contains(sender.tag) else { return }
            actions[sender.tag]()
        }
    }
}
