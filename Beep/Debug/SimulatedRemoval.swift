#if DEBUG
import Foundation
import os

/// Debug builds only: `-simulateRemoved "lesson 2"` makes the sync behave as if WeBeep no longer
/// returned the files whose name contains that text (case-insensitive), in every course.
///
/// Everything downstream is the real path: the file is marked as removed, its local copy is
/// renamed in the sync folder and it moves to the "Removed from WeBeep" group. Launching again
/// without the argument brings the file back as new, which is the "hidden and shown again" case
/// described in docs/removed-files.md.
nonisolated enum SimulatedRemoval {
    static let needle: String? = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-simulateRemoved"), args.indices.contains(i + 1) else { return nil }
        let text = args[i + 1].trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }()

    private static let log = Logger(subsystem: "com.mattiacolombo.Beep", category: "sync")

    static func apply(_ sections: [SectionDTO], needle: String? = needle) -> [SectionDTO] {
        guard let needle else { return sections }
        var dropped = 0
        let result = sections.map { s in
            SectionDTO(id: s.id, name: s.name, section: s.section, summary: s.summary, visible: s.visible, uservisible: s.uservisible,
                       modules: s.modules.map { m in
                let kept = m.contents?.filter { !($0.type == "file" && $0.filename.localizedCaseInsensitiveContains(needle)) }
                dropped += (m.contents?.count ?? 0) - (kept?.count ?? 0)
                return ModuleDTO(id: m.id, name: m.name, modname: m.modname, instance: m.instance, url: m.url,
                                 description: m.description, visible: m.visible, uservisible: m.uservisible, contents: kept)
            })
        }
        if dropped > 0 { log.notice("simulated removal of \(dropped, privacy: .public) files matching \(needle, privacy: .public)") }
        return result
    }
}
#endif
