import CoreSpotlight
import SwiftData
import SwiftUI
import UIKit

@main
struct BeepApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: AppSession
    @State private var sync: SyncEngine
    @State private var opener: FileOpener
    @State private var renewer: TokenRenewer
    @State private var router = AppRouter()
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
            _sync = State(initialValue: SyncEngine(container: container, downloads: downloads))
            _opener = State(initialValue: FileOpener(downloads: downloads))
            _renewer = State(initialValue: TokenRenewer(session: session))
            if DemoData.isEnabled {
                try DemoData.seed(into: container.mainContext)
                session.enterDemo()
            }
        } catch {
            fatalError("Cannot open the local store: \(error)")
        }
        UserDefaults.standard.register(defaults: ["settings.backgroundRefresh": true, "settings.notifications": true, "settings.refreshMinutes": 120.0, "settings.backgroundWifiOnly": false])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(sync)
                .environment(opener)
                .environment(renewer)
                .environment(router)
                .onOpenURL { router.handle(url: $0) }
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let d = SpotlightIndexer.destination(for: activity) { router.open(d) }
                }
                .task {
                    AppServices.session = session
                    AppServices.sync = sync
                    AppServices.router = router
                    appDelegate.downloads = downloads
                    sync.onInvalidToken = { trigger in
                        session.markExpired()
                        if trigger == .background || UIApplication.shared.applicationState != .active {
                            Notifier.notifySessionExpired()
                        }
                    }
                    session.onUserChanged = {
                        let ctx = container.mainContext
                        try? ctx.delete(model: Course.self)
                        try? ctx.delete(model: WebeepNotification.self)
                        try? ctx.save()
                        UserDefaults.standard.removeObject(forKey: "onboarding.done")
                    }
                    appDelegate.onBackgroundRefresh = { task in
                        let work = Task {
                            // Respect Low Power Mode: skip the whole check, reschedule.
                            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                                BackgroundRefresh.schedule()
                            } else if let client = session.client, let user = session.user, user.id != 0 {
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
        .commands { BeepCommands(session: session, sync: sync, router: router) }
    }
}
