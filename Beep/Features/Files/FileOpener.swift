import Foundation
import Observation
import QuickLook
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Coordinates opening, sharing and (single) downloading of files from the UI.
/// Downloads go through the background `DownloadManager`.
@Observable
final class FileOpener {
    var previewURL: URL?
    /// Files handed to the system share sheet (one or many).
    var shareURLs: [URL]?
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
        Task { _ = await share([file]) }
    }

    /// Shares several files at once, downloading the missing ones first (priority queue).
    /// Files that fail to download are skipped; returns whether the sheet was shown and how many failed.
    /// With `present: false` the caller shows the sheet itself (e.g. anchored to its button).
    @discardableResult
    func share(_ files: [FileItem], present: Bool = true, progress: ((Int) -> Void)? = nil) async -> (urls: [URL], failed: Int) {
        var urls: [URL] = []
        var failed = 0
        for (i, file) in files.enumerated() {
            if let url = try? await localURL(for: file) { urls.append(url) } else { failed += 1 }
            progress?(i + 1)
        }
        if present, !urls.isEmpty { shareURLs = urls }
        return (urls, failed)
    }

    func showInFiles(_ file: FileItem) {
        guard let url = local.url(for: file) else { return }
        Platform.reveal(url)
    }

    /// The course's folder on disk (this edition), if anything was downloaded.
    func directory(of course: Course) -> URL? { local.directory(of: course) }

    /// A folder module's directory on disk, if anything was downloaded.
    func directory(of module: CourseModule) -> URL? { local.directory(of: module) }

    func reveal(_ folder: URL) { Platform.reveal(folder) }

    /// Runs `LocalFiles.migrateLayout` once per download root (the Mac folder can change).
    /// Returns how many files were moved, so the UI can tell the user once.
    func migrateLayout(context: ModelContext) -> Int {
        let key = "files.layout2." + local.root.standardizedFileURL.path(percentEncoded: false)
        guard !UserDefaults.standard.bool(forKey: key),
              FileManager.default.fileExists(atPath: local.root.path(percentEncoded: false)) else { return 0 }
        let courses = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        let moved = local.migrateLayout(courses: courses)
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
        return moved
    }

    /// Opens the download root in Finder (Mac) or the Files app (iOS).
    func openDownloadRoot() { Platform.openFolder(local.root) }

    /// Copies the full on-disk path of a downloaded file to the clipboard.
    func copyPath(of file: FileItem) {
        guard let url = local.url(for: file) else { return }
        Platform.copyToClipboard(url.path(percentEncoded: false))
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
        var parts = file.course?.folderDirectory.map(Self.sanitize) ?? ["Course"]
        if let module = file.module, module.kind == .folder { parts.append(Self.sanitize(module.name)) }
        for sub in file.filepath.split(separator: "/") where !sub.isEmpty { parts.append(Self.sanitize(String(sub))) }
        parts.append(Self.sanitize(file.filename))
        return parts.joined(separator: "/")
    }

    /// Existing directory of a course edition, or nil when nothing was downloaded yet.
    func directory(of course: Course) -> URL? {
        existingDirectory(root.appending(path: course.folderDirectory.map(Self.sanitize).joined(separator: "/")))
    }

    /// Existing directory of a folder module (other module kinds put files straight in the course folder).
    func directory(of module: CourseModule) -> URL? {
        guard module.kind == .folder, let course = module.section?.course,
              let courseDir = directory(of: course) else { return nil }
        return existingDirectory(courseDir.appending(path: Self.sanitize(module.name)))
    }

    private func existingDirectory(_ url: URL) -> URL? {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue ? url : nil
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

    /// Moves this edition's folder to a new course folder name and rewrites the stored relative
    /// paths. Other editions of the course keep their own year sub-folder. Merges into an
    /// existing folder with the same name.
    func renameCourseFolder(_ course: Course, to requested: String) throws {
        let newName = Self.sanitize(requested)
        let oldName = Self.sanitize(course.folderName.isEmpty ? course.title : course.folderName)
        guard newName != oldName else { return }
        let year = course.isAcademicYear ? Self.sanitize(course.categoryName) : nil
        let oldParts = [oldName] + (year.map { [$0] } ?? [])
        let newParts = [newName] + (year.map { [$0] } ?? [])
        try Self.moveMerging(root.appending(path: oldParts.joined(separator: "/")), into: root.appending(path: newParts.joined(separator: "/")))
        if year != nil { removeEmptyDirectories(from: root.appending(path: oldName)) }
        let oldPrefix = oldParts.joined(separator: "/") + "/"
        let newPrefix = newParts.joined(separator: "/") + "/"
        for file in course.files {
            if let rel = file.localRelativePath, rel.hasPrefix(oldPrefix) {
                file.localRelativePath = newPrefix + rel.dropFirst(oldPrefix.count)
            }
        }
        course.folderName = newName
    }

    /// Moves `source` to `target`; when `target` exists, its contents are merged (replacing files).
    private static func moveMerging(_ source: URL, into target: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path(percentEncoded: false)) else { return }
        if fm.fileExists(atPath: target.path(percentEncoded: false)) {
            for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let dest = target.appending(path: item.lastPathComponent)
                if fm.fileExists(atPath: dest.path(percentEncoded: false)) { try fm.removeItem(at: dest) }
                try fm.moveItem(at: item, to: dest)
            }
            try fm.removeItem(at: source)
        } else {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: source, to: target)
        }
    }

    /// Moves downloads from the flat layout of earlier versions ("Title (Professor)/file", or
    /// "Title/file") into "Title/2026-27/file", and keeps files where `folderDirectory` says when
    /// an edition folder changes (a second section of a course shows up in the same year).
    /// Idempotent: files already in place are left alone, files missing on disk are not touched.
    /// Returns how many files were moved.
    @discardableResult
    func migrateLayout(courses: [Course]) -> Int {
        let fm = FileManager.default
        var emptied: Set<URL> = []
        var moved = 0
        Course.assignEditionFolders(courses)
        for course in courses {
            // Drop the suffixes the old indexer added to tell editions apart; user renames stay.
            let autoNames = [course.professors.map { "\(course.title) (\($0))" }, "\(course.title) (\(course.id))"].compactMap { $0 }
            if autoNames.contains(course.folderName) { course.folderName = course.title }
            for file in course.files {
                guard let rel = file.localRelativePath else { continue }
                let target = relativePath(for: file)
                guard rel != target else { continue }
                let src = root.appending(path: rel), dst = root.appending(path: target)
                guard fm.fileExists(atPath: src.path(percentEncoded: false)) else { continue }
                do {
                    try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dst.path(percentEncoded: false)) { try fm.removeItem(at: dst) }
                    try fm.moveItem(at: src, to: dst)
                    file.localRelativePath = target
                    emptied.insert(src.deletingLastPathComponent())
                    moved += 1
                } catch { continue }
            }
        }
        for dir in emptied { removeEmptyDirectories(from: dir) }
        return moved
    }

    /// Removes `dir` and then its parents while they are empty, never the root itself.
    private func removeEmptyDirectories(from dir: URL) {
        func path(_ url: URL) -> String {
            var p = url.standardizedFileURL.path(percentEncoded: false)
            while p.count > 1, p.hasSuffix("/") { p.removeLast() }
            return p
        }
        let rootPath = path(root)
        var current = dir
        while path(current) != rootPath, path(current).hasPrefix(rootPath + "/") {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: path(current)),
                  items.allSatisfy({ $0 == ".DS_Store" }) else { return }
            try? FileManager.default.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
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
