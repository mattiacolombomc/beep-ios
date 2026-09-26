import SwiftUI

/// Bottom bar shown while selecting files: select all, count, share.
struct FileSelectionBar: View {
    /// Files the user can select on this screen, in display order.
    let candidates: [FileItem]
    @Environment(FileSelection.self) private var selection
    @Environment(FileOpener.self) private var opener
    #if os(macOS)
    @State private var pickerURLs: [URL]?
    #endif

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Group {
                if selection.allSelected(in: candidates) {
                    Button("Deselect All") { selection.deselectAll() }
                } else {
                    Button("Select All") { selection.selectAll(candidates) }
                }
            }
            .disabled(candidates.isEmpty || selection.isPreparing)
            Spacer()
            if let p = selection.preparing {
                HStack(spacing: Theme.Spacing.s) {
                    ProgressView().controlSize(.small)
                    Text("Preparing \(p.done) of \(p.total)…").monospacedDigit()
                }
                .font(.subheadline).foregroundStyle(.secondary)
            } else if selection.failedCount > 0 {
                Text("Couldn't download \(selection.failedCount) files").font(.subheadline).foregroundStyle(.red)
            } else {
                Text("\(selection.count) selected").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            Button {
                Task { await share() }
            } label: {
                // Full label when there is room (iPad, Mac), icon only on a phone.
                ViewThatFits(in: .horizontal) {
                    Label("Share", systemImage: "square.and.arrow.up")
                    Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selection.count == 0 || selection.isPreparing)
            #if os(macOS)
            .background(MacSharePicker(urls: $pickerURLs) { selection.end() })
            #endif
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s + 2)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func share() async {
        let files = selection.selected(from: candidates)
        selection.failedCount = 0
        selection.preparing = (0, files.count)
        #if os(macOS)
        // The picker is anchored to the Share button: keep the bar until the picker closes.
        let outcome = await opener.share(files, present: false) { done in selection.preparing = (done, files.count) }
        selection.preparing = nil
        if !outcome.urls.isEmpty { pickerURLs = outcome.urls } else { selection.failedCount = outcome.failed }
        #else
        let outcome = await opener.share(files) { done in selection.preparing = (done, files.count) }
        selection.preparing = nil
        if !outcome.urls.isEmpty { selection.end() } else { selection.failedCount = outcome.failed }
        #endif
    }
}

/// Hosts the selection bar under a list as a bottom safe-area inset (content scrolls beneath it).
private struct SelectionBarHost: ViewModifier {
    let selection: FileSelection
    let candidates: [FileItem]

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if selection.isActive { FileSelectionBar(candidates: candidates) }
        }
    }
}

extension View {
    /// Shows the multi-select bar while `FileSelection` (from the environment) is active.
    func selectionBar(_ selection: FileSelection, candidates: [FileItem]) -> some View {
        modifier(SelectionBarHost(selection: selection, candidates: candidates))
    }
}
