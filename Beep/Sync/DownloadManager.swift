import Foundation
import Observation
import SwiftData
import UIKit

/// Background-URLSession download queue. Survives app suspension and relaunch:
/// each task carries the file key + destination path in `taskDescription`, so
/// the (nonisolated) delegate can move the file without touching SwiftData,
/// then hops to the main actor to update the model.
@Observable
final class DownloadManager {
    static let sessionIdentifier = "com.mattiacolombo.Beep.downloads"

    struct Progress: Equatable {
        var active = 0
        var queued = 0
        var completedInSession = 0
        var failedInSession = 0
        var currentFileName: String?
        var bytesReceived: Int64 = 0
        var bytesExpected: Int64 = 0
        var isBusy: Bool { active + queued > 0 }
        var total: Int { active + queued + completedInSession + failedInSession }
        var fraction: Double {
            guard total > 0 else { return 0 }
            return Double(completedInSession + failedInSession) / Double(total)
        }
    }

    private(set) var progress = Progress()
    private(set) var fileProgress: [String: Double] = [:]

    private let context: ModelContext
    private let local: LocalFiles
    private let maxConcurrent = 3
    private var session: URLSession!
    private let delegate: Delegate
    private var queue: [String] = []                 // file keys waiting
    private var inFlight: [String: URLSessionDownloadTask] = [:]
    private var completions: [String: [() -> Void]] = [:]
    /// Set by the app delegate when iOS relaunches us for background events.
    var backgroundCompletionHandler: (() -> Void)?

    init(context: ModelContext, local: LocalFiles = LocalFiles()) {
        self.context = context
        self.local = local
        self.delegate = Delegate()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true
        config.httpMaximumConnectionsPerHost = maxConcurrent
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        delegate.manager = self
        delegate.root = local.root
        reconcile()
    }

    // MARK: Public API

    /// Queue a file. `priority: true` jumps the queue (user tapped it).
    func enqueue(_ file: FileItem, priority: Bool = false, completion: (() -> Void)? = nil) {
        if let completion { completions[file.key, default: []].append(completion) }
        guard inFlight[file.key] == nil else { return }
        if queue.contains(file.key) {
            if priority, let i = queue.firstIndex(of: file.key) { queue.remove(at: i); queue.insert(file.key, at: 0) }
            return
        }
        file.state = .queued
        file.lastError = nil
        if priority { queue.insert(file.key, at: 0) } else { queue.append(file.key) }
        progress.queued = queue.count
        pump()
    }

    /// `background: true` marks the batch as opportunistic: Wi-Fi only if the user asked for it.
    func enqueue(_ files: [FileItem], background: Bool = false) {
        if background, UserDefaults.standard.bool(forKey: "settings.backgroundWifiOnly") {
            deferredKeys.formUnion(files.filter { !$0.isDownloaded || $0.hasUpdate }.map(\.key))
            return
        }
        for f in files where !f.isDownloaded || f.hasUpdate { enqueue(f) }
    }

    /// Files postponed by a background check; flushed on the next foreground sync.
    private(set) var deferredKeys: Set<String> = []

    func flushDeferred() {
        guard !deferredKeys.isEmpty else { return }
        let keys = deferredKeys
        deferredKeys.removeAll()
        for key in keys { if let f = file(for: key) { enqueue(f) } }
    }

    func cancelAll() {
        for (_, task) in inFlight { task.cancel() }
        inFlight.removeAll()
        for key in queue { if let f = file(for: key) { f.state = .notDownloaded } }
        queue.removeAll()
        progress = Progress()
        fileProgress.removeAll()
    }

    func resetSessionCounters() {
        if !progress.isBusy { progress = Progress() }
    }

    // MARK: Queue mechanics

    private func pump() {
        while inFlight.count < maxConcurrent, !queue.isEmpty {
            let key = queue.removeFirst()
            guard let file = file(for: key), let url = URL(string: file.remoteURL) else { continue }
            let rel = local.relativePath(for: file)
            let task = session.downloadTask(with: url)
            task.taskDescription = Delegate.describe(key: key, relativePath: rel, filename: file.filename)
            task.countOfBytesClientExpectsToReceive = Int64(max(file.filesize, 1))
            inFlight[key] = task
            file.state = .downloading
            fileProgress[key] = 0
            task.resume()
        }
        progress.queued = queue.count
        progress.active = inFlight.count
        progress.currentFileName = inFlight.values.first?.taskDescription.flatMap(Delegate.parse)?.filename
    }

    private func file(for key: String) -> FileItem? {
        var d = FetchDescriptor<FileItem>(predicate: #Predicate { $0.key == key })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// On launch: files left in queued/downloading state that have no live task go back to notDownloaded.
    private func reconcile() {
        session.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var live: Set<String> = []
                for t in tasks {
                    if let d = t.taskDescription, let info = Delegate.parse(d), let dt = t as? URLSessionDownloadTask {
                        live.insert(info.key)
                        self.inFlight[info.key] = dt
                    }
                }
                let stale = try? self.context.fetch(FetchDescriptor<FileItem>(predicate: #Predicate { $0.stateRaw == 1 || $0.stateRaw == 2 }))
                for f in stale ?? [] where !live.contains(f.key) { f.state = .notDownloaded }
                for f in stale ?? [] where live.contains(f.key) { f.state = .downloading }
                self.progress.active = self.inFlight.count
                self.progress.currentFileName = self.inFlight.values.first?.taskDescription.flatMap(Delegate.parse)?.filename
            }
        }
    }

    // MARK: Delegate callbacks (already on main actor)

    fileprivate func didProgress(key: String, received: Int64, expected: Int64) {
        if expected > 0 { fileProgress[key] = min(Double(received) / Double(expected), 0.99) }
    }

    fileprivate func didFinish(key: String, relativePath: String?, error: String?) {
        inFlight.removeValue(forKey: key)
        fileProgress.removeValue(forKey: key)
        if let file = file(for: key) {
            if let error {
                file.state = .failed
                file.lastError = error
                progress.failedInSession += 1
            } else {
                file.localRelativePath = relativePath
                file.downloadedTimemodified = file.timemodified
                file.state = .downloaded
                file.lastError = nil
                progress.completedInSession += 1
            }
            try? context.save()
        }
        let callbacks = completions.removeValue(forKey: key) ?? []
        if error == nil { for cb in callbacks { cb() } }
        pump()
    }

    fileprivate func didFinishAllBackgroundEvents() {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    // MARK: URLSession delegate (nonisolated)

    final class Delegate: NSObject, URLSessionDownloadDelegate, Sendable {
        nonisolated(unsafe) weak var manager: DownloadManager?
        nonisolated(unsafe) var root: URL = .documentsDirectory

        struct Info: Codable { let key: String; let relativePath: String; let filename: String }

        static func describe(key: String, relativePath: String, filename: String) -> String {
            (try? String(data: JSONEncoder().encode(Info(key: key, relativePath: relativePath, filename: filename)), encoding: .utf8)) ?? key
        }
        static func parse(_ description: String) -> Info? {
            try? JSONDecoder().decode(Info.self, from: Data(description.utf8))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
            guard let info = downloadTask.taskDescription.flatMap(Self.parse) else { return }
            if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let status = http.statusCode
                Task { @MainActor in self.manager?.didFinish(key: info.key, relativePath: nil, error: "HTTP \(status)") }
                return
            }
            let dest = root.appending(path: info.relativePath)
            do {
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.moveItem(at: location, to: dest)
                Task { @MainActor in self.manager?.didFinish(key: info.key, relativePath: info.relativePath, error: nil) }
            } catch {
                let message = String(describing: error)
                Task { @MainActor in self.manager?.didFinish(key: info.key, relativePath: nil, error: message) }
            }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            guard let info = downloadTask.taskDescription.flatMap(Self.parse) else { return }
            Task { @MainActor in self.manager?.didProgress(key: info.key, received: totalBytesWritten, expected: totalBytesExpectedToWrite) }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let error, let info = task.taskDescription.flatMap(Self.parse) else { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            let message = error.localizedDescription
            Task { @MainActor in self.manager?.didFinish(key: info.key, relativePath: nil, error: message) }
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            Task { @MainActor in self.manager?.didFinishAllBackgroundEvents() }
        }
    }
}
