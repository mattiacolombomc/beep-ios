import Foundation
import Testing

/// Source rules that keep the Mac UI responsive. Each one encodes a measured regression
/// (October 2026, Instruments samples and the BENCH harnesses): breaking a rule brought back
/// a toolbar that rebuilds itself or a window that re-lays out on every click or keystroke.
struct UIArchitectureTests {
    /// Repository root, from this file's location (BeepTests/UIArchitectureTests.swift).
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private struct Source { let path: String; let lines: [String] }

    private static func sources(in folders: [String]) -> [Source] {
        folders.flatMap { folder -> [Source] in
            let dir = root.appending(path: folder)
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
            return e.compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" }
                .compactMap { url in
                    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                    let rel = url.path(percentEncoded: false).replacingOccurrences(of: root.path(percentEncoded: false), with: "")
                    return Source(path: rel, lines: text.components(separatedBy: "\n"))
                }
        }
    }

    /// For every line, whether it is compiled for macOS according to `#if os(...)` blocks
    /// (other conditions are treated as compiled on every platform).
    private static func compiledOnMac(_ lines: [String]) -> [Bool] {
        var stack: [(mac: Bool, isOSCheck: Bool)] = []
        var result: [Bool] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#if ") {
                if line.contains("os(macOS)") { stack.append((true, true)) }
                else if line.contains("os(iOS)") { stack.append((false, true)) }
                else { stack.append((true, false)) }
                result.append(true); continue
            }
            if line.hasPrefix("#else"), let top = stack.popLast() {
                stack.append((top.isOSCheck ? !top.mac : true, top.isOSCheck))
                result.append(true); continue
            }
            if line.hasPrefix("#endif") { _ = stack.popLast(); result.append(true); continue }
            result.append(stack.allSatisfy(\.mac))
        }
        return result
    }

    /// Top-level type declarations with their lines.
    private static func types(in source: Source) -> [(header: String, body: [String])] {
        var out: [(String, [String])] = []
        var current: (String, [String])?
        for line in source.lines {
            let isTop = !line.hasPrefix(" ") && !line.hasPrefix("\t")
                && (line.contains("struct ") || line.contains("class ") || line.contains("enum ") || line.hasPrefix("extension "))
            if isTop {
                if let c = current { out.append(c) }
                current = (line, [])
            } else {
                current?.1.append(line)
            }
        }
        if let c = current { out.append(c) }
        return out
    }

    @Test func searchableIsNeverCompiledForTheMac() {
        var offenders: [String] = []
        for source in Self.sources(in: ["Beep", "BeepMac"]) {
            let mac = Self.compiledOnMac(source.lines)
            for (i, line) in source.lines.enumerated() where line.contains(".searchable(") && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") && mac[i] {
                offenders.append("\(source.path):\(i + 1)")
            }
        }
        #expect(offenders.isEmpty, """
            On macOS `.searchable` is a toolbar item: every keystroke changes a toolbar preference and \
            SwiftUI recreates every toolbar item (the section bar flashes, open menus close, 200+ ms per \
            keystroke). Use `ToolbarSearch` / `SidebarSearchField` on the Mac and keep `.searchable` in an \
            `#if os(iOS)` branch. Offenders: \(offenders)
            """)
    }

    @Test func viewsWithLiveDataDoNotDeclareToolbarsInline() {
        // A `.toolbar` inside a view that re-renders on every keystroke or database change is
        // re-emitted on each render, and AppKit rebuilds the window toolbar. Such views move their
        // toolbar into a modifier whose inputs are references (see `CourseToolbar`).
        let liveState = ["@Query", "SearchText()", "private var query", "@State private var results"]
        // Sheets and settings panes: their toolbar is their own window's, and nothing in them
        // changes while typing.
        let allowed: Set<String> = ["NotificationsView", "SettingsView", "LoginView", "CatalogSearchView",
                                    "OnboardingFlow", "PageView", "NotificationDetailView"]
        var offenders: [String] = []
        for source in Self.sources(in: ["Beep/Features", "BeepMac"]) {
            for type in Self.types(in: source) where type.header.range(of: #": View( |\{|,|$)"#, options: .regularExpression) != nil {
                let name = type.header.components(separatedBy: "struct ").last?.components(separatedBy: CharacterSet(charactersIn: ":<")).first?.trimmingCharacters(in: .whitespaces) ?? type.header
                guard !allowed.contains(name) else { continue }
                let body = type.body.joined(separator: "\n")
                if liveState.contains(where: body.contains) && body.contains(".toolbar {") {
                    offenders.append("\(source.path) \(name)")
                }
            }
        }
        #expect(offenders.isEmpty, "Move these toolbars into a reference-input modifier: \(offenders)")
    }

    @Test func indexingNeverRunsOnAModelActor() {
        let offenders = Self.sources(in: ["Beep", "BeepMac"]).filter { src in
            src.lines.contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("@ModelActor") }
        }.map(\.path)
        #expect(offenders.isEmpty, """
            On this SDK a @ModelActor ran every call on the main thread, even when created off it: a             sync blocked the UI for 32 of 34 seconds. Use a plain actor that owns its ModelContext             (see IndexActor). Offenders: \(offenders)
            """)
    }

    @Test func toolbarSyncButtonDoesNotFollowEveryCourse() throws {
        let text = try String(contentsOf: Self.root.appending(path: "BeepMac/MacMainView.swift"), encoding: .utf8)
        let start = try #require(text.range(of: "struct SyncButton")).lowerBound
        let rest = text[start...]
        let button = String(rest[..<(rest.range(of: "\n}\n")?.upperBound ?? rest.endIndex)])
        #expect(!button.contains("sync.phase"),
                "The toolbar Sync button must read `isIndexing` only: reading `phase` re-tiled the toolbar once per course. The bar and counter are the AppKit `SyncProgressLabel`.")
    }

    @Test func macSectionsStayMountedAndAttached() throws {
        let text = try String(contentsOf: Self.root.appending(path: "BeepMac/MacMainView.swift"), encoding: .utf8)
        let layer = try #require(text.range(of: "private struct SectionLayer")).lowerBound
        let layerBody = String(text[layer...].prefix(1200))
        let content = try #require(text.range(of: "private var content: some View")).lowerBound
        let contentBody = String(text[content...].prefix(1500))
        #expect(!contentBody.contains("switch router.selectedTab") && contentBody.contains("SectionLayer("),
                "Switching on the selected section rebuilds the split view and lists on every click (~400 ms).")
        #expect(layerBody.contains("0.001"),
                "Hidden sections keep a near-zero opacity: SwiftUI detaches fully transparent views and re-attaches them.")
        #expect(!layerBody.contains(".allowsHitTesting(") && !layerBody.contains(".accessibilityHidden("),
                "Toggling hit testing or accessibility on a section made SwiftUI re-attach its lists on every switch.")
    }
}
