import AppKit
import Foundation
import Observation

/// The folder where Beep for Mac keeps course material (e.g. ~/Desktop/WeBeep).
/// The sandbox only lets us write where the user pointed us, so the choice is stored
/// as a security-scoped bookmark and re-opened at every launch.
@Observable
final class DownloadFolder {
    private static let bookmarkKey = "mac.downloadFolderBookmark"

    /// The chosen folder, nil until the user picks one.
    private(set) var url: URL?
    private(set) var lastError: String?

    init() { restore() }

    var isChosen: Bool { url != nil }

    /// Re-opens the saved bookmark and points downloads at it.
    func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let resolved = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale),
              resolved.startAccessingSecurityScopedResource() else {
            lastError = String(localized: "The download folder is no longer available. Choose it again in Settings.")
            return
        }
        if stale, let fresh = try? resolved.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        url = resolved
        DownloadLocation.root = resolved
        lastError = nil
    }

    /// Adopts `newURL` (from the folder picker) and moves what was already downloaded there,
    /// keeping each file's path relative to the root, so nothing has to be downloaded again.
    func choose(_ newURL: URL) {
        let gotAccess = newURL.startAccessingSecurityScopedResource()
        do {
            let bookmark = try newURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let oldRoot = DownloadLocation.root
            if oldRoot.standardizedFileURL != newURL.standardizedFileURL {
                moveContents(from: oldRoot, to: newURL)
            }
            url?.stopAccessingSecurityScopedResource()
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
            url = newURL
            DownloadLocation.root = newURL
            lastError = nil
        } catch {
            if gotAccess { newURL.stopAccessingSecurityScopedResource() }
            lastError = error.localizedDescription
        }
    }

    func showInFinder() {
        Platform.openFolder(url ?? DownloadLocation.root)
    }

    /// Moves top-level course folders; anything already present at the destination is kept.
    private func moveContents(from old: URL, to new: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: old, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for item in items {
            let dest = new.appending(path: item.lastPathComponent)
            guard !fm.fileExists(atPath: dest.path(percentEncoded: false)) else { continue }
            try? fm.moveItem(at: item, to: dest)
        }
    }
}
