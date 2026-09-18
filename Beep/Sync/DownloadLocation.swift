import Foundation

/// Where downloaded course material lives. iOS: the app's Documents folder (shown in
/// Files as "On My iPhone › Beep"). macOS: a folder the user picks, e.g. on the Desktop,
/// set at launch from a security-scoped bookmark and changeable at runtime.
nonisolated enum DownloadLocation {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: URL = URL.documentsDirectory

    static var root: URL {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
