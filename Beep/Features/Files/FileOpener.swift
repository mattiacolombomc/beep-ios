import Foundation
import Observation
import QuickLook
import SwiftUI
import UIKit

/// Coordinates opening, sharing and (single) downloading of files from the UI.
/// Downloads go through the background `DownloadManager`.
@Observable
final class FileOpener {
    var previewURL: URL?
    var shareURL: URL?
    private let local: LocalFiles
    private let downloads: DownloadManager

    init(downloads: DownloadManager, local: LocalFiles = LocalFiles()) {
        self.downloads = downloads
        self.local = local
    }

    func progress(for file: FileItem) -> Double { downloads.fileProgress[file.key] ?? 0 }

    func open(_ file: FileItem) {
        if file.isDownloaded, let url = local.url(for: file) {
            previewURL = url
            return
        }
        downloads.enqueue(file, priority: true) { [weak self] in
            guard let self, let url = self.local.url(for: file) else { return }
            self.previewURL = url
        }
    }

    func download(_ file: FileItem) {
        downloads.enqueue(file, priority: true)
    }

    func share(_ file: FileItem) {
        shareURL = local.url(for: file)
    }

    func showInFiles(_ file: FileItem) {
        guard let url = local.url(for: file) else { return }
        var comps = URLComponents(url: url.deletingLastPathComponent(), resolvingAgainstBaseURL: false)
        comps?.scheme = "shareddocuments"
        if let target = comps?.url { UIApplication.shared.open(target) }
    }

    func removeLocal(_ file: FileItem) {
        local.remove(file)
        file.localRelativePath = nil
        file.downloadedTimemodified = nil
        file.state = .notDownloaded
    }
}

/// Where downloads live: Documents/<Course>/<Module>/<subpath>/<file>, visible in the Files app.
struct LocalFiles: Sendable {
    let root: URL

    init(root: URL = URL.documentsDirectory) { self.root = root }

    nonisolated static func sanitize(_ component: String) -> String {
        var s = component.replacing(/[\/:\\]/, with: "-")
        s = s.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return s.isEmpty ? "_" : String(s.prefix(120))
    }

    /// Relative path for a file, computed from its course/module/filepath.
    func relativePath(for file: FileItem) -> String {
        var parts: [String] = []
        let folder = file.course.map { $0.folderName.isEmpty ? $0.title : $0.folderName } ?? "Course"
        parts.append(Self.sanitize(folder))
        if let module = file.module, module.kind == .folder { parts.append(Self.sanitize(module.name)) }
        for sub in file.filepath.split(separator: "/") where !sub.isEmpty { parts.append(Self.sanitize(String(sub))) }
        parts.append(Self.sanitize(file.filename))
        return parts.joined(separator: "/")
    }

    func url(for file: FileItem) -> URL? {
        guard let rel = file.localRelativePath else { return nil }
        let url = root.appending(path: rel)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    func store(_ temp: URL, for file: FileItem) throws {
        let rel = relativePath(for: file)
        let dest = root.appending(path: rel)
        try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.moveItem(at: temp, to: dest)
        file.localRelativePath = rel
    }

    func remove(_ file: FileItem) {
        guard let url = url(for: file) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Bytes on disk under the root (downloaded material).
    func usedBytes() -> Int {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in e {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}
