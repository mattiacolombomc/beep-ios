import Foundation
import SwiftData
import Testing
@testable import Beep

@MainActor
struct FileSelectionTests {
    private func file(_ key: String) -> FileItem {
        FileItem(key: key, filename: "\(key).pdf", filepath: "/", filesize: 1, timemodified: .now, mimetype: nil, remoteURL: "https://x/\(key)", firstSeenAt: .now)
    }

    @Test func toggleSelectAllAndEnd() {
        let files = [file("a"), file("b"), file("c")]
        let s = FileSelection()
        #expect(!s.isActive)
        s.begin()
        s.toggle(files[0])
        #expect(s.isSelected(files[0]) && s.count == 1)
        s.toggle(files[0])
        #expect(s.count == 0)
        s.selectAll(files)
        #expect(s.allSelected(in: files))
        s.toggle(files[1])
        #expect(!s.allSelected(in: files))
        #expect(s.selected(from: files).map(\.key) == ["a", "c"])  // display order, not insertion order
        s.end()
        #expect(!s.isActive && s.count == 0 && s.preparing == nil)
    }

    @Test func allSelectedIsFalseForEmptyCandidates() {
        let s = FileSelection()
        #expect(!s.allSelected(in: []))
    }
}
