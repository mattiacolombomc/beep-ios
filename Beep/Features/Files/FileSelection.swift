import Foundation
import Observation

/// Multi-select state for a list of files (course, Recent, Search). Screens that support
/// selection own one instance and put it in the environment; `FileRow` reads it if present.
@Observable
final class FileSelection {
    private(set) var isActive = false
    private(set) var keys: Set<String> = []
    /// Set while the selected files are being downloaded ahead of sharing.
    var preparing: (done: Int, total: Int)?
    var failedCount = 0

    var count: Int { keys.count }
    var isPreparing: Bool { preparing != nil }

    func begin() { isActive = true }

    func end() {
        isActive = false
        keys.removeAll()
        preparing = nil
        failedCount = 0
    }

    func isSelected(_ file: FileItem) -> Bool { keys.contains(file.key) }

    func toggle(_ file: FileItem) {
        if keys.contains(file.key) { keys.remove(file.key) } else { keys.insert(file.key) }
    }

    func allSelected(in candidates: [FileItem]) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy { keys.contains($0.key) }
    }

    func selectAll(_ candidates: [FileItem]) { keys.formUnion(candidates.map(\.key)) }
    func deselectAll() { keys.removeAll() }

    /// The selected files, in the order they appear on screen.
    func selected(from candidates: [FileItem]) -> [FileItem] { candidates.filter { keys.contains($0.key) } }
}
