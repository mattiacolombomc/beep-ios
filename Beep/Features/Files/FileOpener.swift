import Foundation
import Observation
import QuickLook
import SwiftUI
import UIKit

/// Coordinates opening, sharing and downloading files from the UI.
/// M1: single foreground downloads. M2 swaps the transport for the background DownloadManager.
@Observable
final class FileOpener {
    var previewURL: URL?
    var shareURL: URL?
    private(set) var progressByKey: [String: Double] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private let local: LocalFiles

    init(local: LocalFiles = LocalFiles()) {
        self.local = local
    }

    func progress(for file: FileItem) -> Double { progressByKey[file.key] ?? 0 }

    func open(_ file: FileItem) {
        if file.isDownloaded, let url = local.url(for: file) {
            previewURL = url
            return
        }
        download(file) { [weak self] in
            guard let self, let url = self.local.url(for: file) else { return }
            self.previewURL = url
        }
    }

    func share(_ file: FileItem) {
        shareURL = local.url(for: file)
    }

    func showInFiles(_ file: FileItem) {
        guard let url = local.url(for: file) else { return }
        // Files app deep link: swap the scheme, keep the path.
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

    func download(_ file: FileItem, completion: (() -> Void)? = nil) {
        guard tasks[file.key] == nil, let url = URL(string: file.remoteURL) else { return }
        file.state = .downloading
        progressByKey[file.key] = 0
        tasks[file.key] = Task {
            defer { tasks[file.key] = nil; progressByKey[file.key] = nil }
            do {
                let (bytes, response) = try await URLSession.shared.bytes(from: url)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw MoodleError.http(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
                }
                let expected = Double(http.expectedContentLength)
                let temp = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
                FileManager.default.createFile(atPath: temp.path(percentEncoded: false), contents: nil)
                let handle = try FileHandle(forWritingTo: temp)
                var buffer = Data(); buffer.reserveCapacity(64 * 1024)
                var received: Double = 0
                for try await byte in bytes {
                    buffer.append(byte)
                    if buffer.count >= 64 * 1024 {
                        try handle.write(contentsOf: buffer)
                        received += Double(buffer.count)
                        buffer.removeAll(keepingCapacity: true)
                        if expected > 0 { progressByKey[file.key] = min(received / expected, 0.99) }
                    }
                }
                try handle.write(contentsOf: buffer)
                try handle.close()
                try local.store(temp, for: file)
                file.downloadedTimemodified = file.timemodified
                file.state = .downloaded
                file.lastError = nil
                completion?()
            } catch {
                file.state = .failed
                file.lastError = String(describing: error)
            }
        }
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
        parts.append(Self.sanitize(file.course?.title ?? "Course"))
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
}
