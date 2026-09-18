import SwiftData
import SwiftUI

@main
struct BeepMacApp: App {
    @State private var session: AppSession
    @State private var sync: SyncEngine
    @State private var opener: FileOpener
    @State private var renewer: TokenRenewer
    @State private var router: AppRouter
    @State private var folder: DownloadFolder
    private let scheduler: MacSyncScheduler
    private let container: ModelContainer

    init() {
        UserDefaults.standard.register(defaults: ["settings.backgroundRefresh": true, "settings.notifications": true, "settings.refreshMinutes": 120.0, "settings.backgroundWifiOnly": false])
        // Resolve the download folder before anything touches LocalFiles.
        let folder = DownloadFolder()
        _folder = State(initialValue: folder)
        let container: ModelContainer
        do {
            container = try StoreContainer.make(inMemory: DemoData.isEnabled)
        } catch {
            fatalError("Cannot open the local store: \(error)")
        }
        self.container = container
        let downloads = DownloadManager(context: container.mainContext)
        let session = AppSession(tokenStore: TokenStore(service: DemoData.isEnabled ? "demo" : "com.mattiacolombo.Beep"))
        let sync = SyncEngine(container: container, downloads: downloads)
        let router = AppRouter()
        _session = State(initialValue: session)
        _sync = State(initialValue: sync)
        _router = State(initialValue: router)
        _opener = State(initialValue: FileOpener(downloads: downloads))
        _renewer = State(initialValue: TokenRenewer(session: session))
        scheduler = MacSyncScheduler(session: session, sync: sync)
        if DemoData.isEnabled {
            try? DemoData.seed(into: container.mainContext)
            session.enterDemo()
        }
        AppServices.session = session
        AppServices.sync = sync
        AppServices.router = router
        sync.onInvalidToken = { [session] trigger in
            session.markExpired()
            if trigger == .background || !NSApplication.shared.isActive {
                Notifier.notifySessionExpired()
            }
        }
        session.onUserChanged = { [container] in
            let ctx = container.mainContext
            try? ctx.delete(model: Course.self)
            try? ctx.delete(model: WebeepNotification.self)
            try? ctx.save()
            UserDefaults.standard.removeObject(forKey: "onboarding.done")
        }
        if !DemoData.isEnabled { session.restore() }
        scheduler.start()
    }

    var body: some Scene {
        Window("Beep", id: "main") {
            RootView()
                .environments(session: session, sync: sync, opener: opener, renewer: renewer, router: router, folder: folder)
                .onOpenURL { router.handle(url: $0) }
                .frame(minWidth: 820, minHeight: 520)
        }
        .modelContainer(container)
        .defaultSize(width: 1180, height: 760)
        .commands { BeepCommands(session: session, sync: sync, router: router) }

        Settings {
            SettingsView()
                .environments(session: session, sync: sync, opener: opener, renewer: renewer, router: router, folder: folder)
                .frame(width: 520, height: 640)
        }
        .modelContainer(container)

        MenuBarExtra {
            MenuBarContent(folder: folder)
                .environments(session: session, sync: sync, opener: opener, renewer: renewer, router: router, folder: folder)
                .modelContainer(container)
        } label: {
            MenuBarIcon(sync: sync)
        }
        .menuBarExtraStyle(.window)
    }
}

private extension View {
    func environments(session: AppSession, sync: SyncEngine, opener: FileOpener, renewer: TokenRenewer, router: AppRouter, folder: DownloadFolder) -> some View {
        environment(session)
            .environment(sync)
            .environment(opener)
            .environment(renewer)
            .environment(router)
            .environment(folder)
    }
}
