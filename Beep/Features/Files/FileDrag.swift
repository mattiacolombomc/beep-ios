import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
/// One file of a multi-item drag (iPadOS 27+): the selected files leave the app together as
/// real files, each downloaded on demand when the receiving app asks for it.
struct DraggedFile: Transferable, Identifiable, Sendable {
    /// `FileItem.key`.
    let id: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { item in
            SentTransferredFile(try await FileDragSource.localURL(forKey: item.id))
        }
        .suggestedFileName { $0.filename }
    }
}

/// Bridges the Transferable export (any isolation) to the main-actor file opener.
@MainActor
enum FileDragSource {
    static weak var opener: FileOpener?

    static func localURL(forKey key: String) async throws -> URL {
        guard let opener else { throw CocoaError(.fileReadNoSuchFile) }
        return try await opener.localURL(forKey: key)
    }
}

/// While selecting, makes a list a drag container whose selection travels as one drag.
struct SelectionDragContainer: ViewModifier {
    let selection: FileSelection
    let candidates: [FileItem]

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            // Names are captured as values: the payload closure runs outside the main actor.
            let names = candidates.reduce(into: [String: String]()) { $0[$1.key] = $1.filename }
            content
                .dragContainer(for: DraggedFile.self) { ids in
                    ids.compactMap { id in names[id].map { DraggedFile(id: id, filename: $0) } }
                }
                .dragContainerSelection(Array(selection.keys))
        } else {
            content
        }
    }
}

/// A row inside `SelectionDragContainer` while selecting.
struct SelectionDragItem: ViewModifier {
    let key: String
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.draggable(containerItemID: key)
        } else {
            content
        }
    }
}
#endif
