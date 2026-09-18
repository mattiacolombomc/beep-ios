import Foundation
import Observation
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

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
            present(url)
            return
        }
        downloads.enqueue(file, priority: true) { [weak self] ok in
            guard ok, let self, let url = self.local.url(for: file) else { return }
            self.present(url)
        }
    }

    /// QuickLook on iOS; on the Mac the file opens in its default app, like any file in Finder.
    private func present(_ url: URL) {
        #if os(iOS)
        previewURL = url
        #else
        Platform.open(url)
        #endif
    }

    /// The file on disk, downloading it first (priority) when needed.
    func localURL(for file: FileItem) async throws -> URL {
        if file.isDownloaded, let url = local.url(for: file) { return url }
        return try await withCheckedThrowingContinuation { continuation in
            downloads.enqueue(file, priority: true) { [local] ok in
                if ok, let url = local.url(for: file) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadNoSuchFile))
                }
            }
        }
    }

    /// Drag payload: the real file, downloaded on demand if it is not on the device yet.
    func itemProvider(for file: FileItem) -> NSItemProvider {
        if file.isDownloaded, let url = local.url(for: file), let provider = NSItemProvider(contentsOf: url) {
            provider.suggestedName = file.filename
            return provider
        }
        let provider = NSItemProvider()
        provider.suggestedName = file.filename
        let type = UTType(filenameExtension: file.fileExtension) ?? .data
        let key = file.key  // models are main-actor bound: carry the key, look the file up again
        provider.registerFileRepresentation(for: type, visibility: .all, openInPlace: false) { [weak self] completion in
            let progress = Progress(totalUnitCount: 1)
            // NSItemProvider's completion may be called from any thread.
            nonisolated(unsafe) let completion = completion
            Task { @MainActor in
                guard let self, let item = self.downloads.file(for: key) else {
                    completion(nil, false, CocoaError(.fileReadNoSuchFile)); return
                }
                do {
                    let url = try await self.localURL(for: item)
                    progress.completedUnitCount = 1
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return progress
        }
        return provider
    }

    func download(_ file: FileItem) {
        downloads.enqueue(file, priority: true)
    }

    func share(_ file: FileItem) {
        shareURL = local.url(for: file)
    }

    func showInFiles(_ file: FileItem) {
        guard let url = local.url(for: file) else { return }
        Platform.reveal(url)
    }

    func renameFolder(of course: Course, to name: String) throws {
        try local.renameCourseFolder(course, to: name)
    }

    func removeLocal(_ file: FileItem) {
        local.remove(file)
        file.localRelativePath = nil
        file.downloadedTimemodified = nil
        file.state = .notDownloaded
    }
}

/// Where downloads live: <root>/<Course>/<Module>/<subpath>/<file>. The root is Documents on iOS
/// (visible in the Files app) and a user-chosen folder on macOS (see `DownloadLocation`).
struct LocalFiles: Sendable {
    /// Set only by tests; otherwise the root follows `DownloadLocation.root`.
    let fixedRoot: URL?
    var root: URL { fixedRoot ?? DownloadLocation.root }

    init(root: URL? = nil) { self.fixedRoot = root }

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

    /// Moves a course's folder to a new name and rewrites the stored relative paths.
    /// Merges into an existing folder with the same name.
    func renameCourseFolder(_ course: Course, to requested: String) throws {
        let newName = Self.sanitize(requested)
        let oldName = course.folderName.isEmpty ? course.title : course.folderName
        guard newName != oldName else { return }
        let oldDir = root.appending(path: oldName)
        let newDir = root.appending(path: newName)
        let fm = FileManager.default
        if fm.fileExists(atPath: oldDir.path(percentEncoded: false)) {
            if fm.fileExists(atPath: newDir.path(percentEncoded: false)) {
                for item in try fm.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil) {
                    let dest = newDir.appending(path: item.lastPathComponent)
                    if fm.fileExists(atPath: dest.path(percentEncoded: false)) { try fm.removeItem(at: dest) }
                    try fm.moveItem(at: item, to: dest)
                }
                try fm.removeItem(at: oldDir)
            } else {
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                try fm.moveItem(at: oldDir, to: newDir)
            }
        }
        for file in course.files {
            if let rel = file.localRelativePath, rel.hasPrefix(oldName + "/") {
                file.localRelativePath = newName + rel.dropFirst(oldName.count)
            }
        }
        course.folderName = newName
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
