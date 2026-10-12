import AppKit
import Observation
import SwiftUI

/// Sync icon that turns into "spinner + 12/56" while a sync runs, updated through
/// Observation directly on the AppKit views, so SwiftUI never re-evaluates the toolbar item.
/// Fixed width: a toolbar item that changes size triggers a toolbar re-layout.
struct SyncToolbarIndicator: NSViewRepresentable {
    let sync: SyncEngine

    func makeCoordinator() -> Coordinator { Coordinator(sync: sync) }

    func makeNSView(context: Context) -> NSView {
        let view = context.coordinator.makeView()
        context.coordinator.track()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    @MainActor
    final class Coordinator {
        private let sync: SyncEngine
        private let icon = NSImageView()
        private let spinner = NSProgressIndicator()
        private let counter = NSTextField(labelWithString: "")

        init(sync: SyncEngine) { self.sync = sync }

        func makeView() -> NSView {
            icon.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: String(localized: "Sync Now"))
            icon.symbolConfiguration = .init(pointSize: 15, weight: .medium)
            icon.contentTintColor = .controlAccentColor
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isDisplayedWhenStopped = false
            counter.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            counter.textColor = .secondaryLabelColor
            counter.alignment = .left
            let stack = NSStackView(views: [icon, spinner, counter])
            stack.orientation = .horizontal
            stack.spacing = 4
            stack.alignment = .centerY
            stack.translatesAutoresizingMaskIntoConstraints = false
            stack.widthAnchor.constraint(equalToConstant: 74).isActive = true
            stack.heightAnchor.constraint(equalToConstant: 22).isActive = true
            render()
            return stack
        }

        /// Re-arms after every change: Observation fires `onChange` once per registration.
        func track() {
            withObservationTracking {
                render()
            } onChange: {
                Task { @MainActor [weak self] in self?.track() }
            }
        }

        private func render() {
            switch sync.phase {
            case .indexing(let done, let total, _):
                icon.isHidden = true
                spinner.startAnimation(nil)
                counter.stringValue = "\(done)/\(total)"
            case .idle, .failed:
                let busy = sync.downloads.progress.isBusy
                icon.isHidden = busy
                if busy { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
                counter.stringValue = busy ? String(localized: "Downloading…") : ""
            }
            counter.toolTip = counter.stringValue
        }
    }
}
