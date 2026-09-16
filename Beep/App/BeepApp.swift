import SwiftData
import SwiftUI

@main
struct BeepApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: AppSession
    @State private var sync: SyncEngine
    @State private var opener: FileOpener
    private let container: ModelContainer
    private let downloads: DownloadManager

    init() {
        do {
            let container = try StoreContainer.make(inMemory: DemoData.isEnabled)
            self.container = container
            let downloads = DownloadManager(context: container.mainContext)
            self.downloads = downloads
            let session = AppSession(tokenStore: TokenStore(service: DemoData.isEnabled ? "demo" : "com.mattiacolombo.Beep"))
            _session = State(initialValue: session)
            _sync = State(initialValue: SyncEngine(context: container.mainContext, downloads: downloads))
            _opener = State(initialValue: FileOpener(downloads: downloads))
            if DemoData.isEnabled {
                try DemoData.seed(into: container.mainContext)
                session.enterDemo()
            }
        } catch {
            fatalError("Cannot open the local store: \(error)")
        }
        UserDefaults.standard.register(defaults: ["settings.backgroundRefresh": true, "settings.notifications": true])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(sync)
                .environment(opener)
                .task {
                    appDelegate.downloads = downloads
                    appDelegate.onBackgroundRefresh = { task in
                        let work = Task {
                            if let client = session.client, let user = session.user, user.id != 0 {
                                _ = await sync.syncAll(client: client, userID: user.id, trigger: .background)
                            }
                            task.setTaskCompleted(success: true)
                        }
                        task.expirationHandler = { work.cancel(); task.setTaskCompleted(success: false) }
                    }
                    if !DemoData.isEnabled { session.restore() }
                }
        }
        .modelContainer(container)
    }
}
