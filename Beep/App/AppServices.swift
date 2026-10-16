import SwiftData
import Foundation

/// Process-wide access to the shared objects for App Intents, which are created outside the SwiftUI scene.
@MainActor
enum AppServices {
    static var session: AppSession?
    static var sync: SyncEngine?
    static var router: AppRouter?
    /// The app's store (performance tests read course ids from it).
    static var container: ModelContainer?
}
