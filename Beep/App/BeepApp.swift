import SwiftData
import SwiftUI

@main
struct BeepApp: App {
    @State private var session: AppSession
    @State private var sync: SyncEngine
    @State private var opener = FileOpener()
    private let container: ModelContainer

    init() {
        do {
            let container = try StoreContainer.make(inMemory: DemoData.isEnabled)
            self.container = container
            let session = AppSession(tokenStore: TokenStore(service: DemoData.isEnabled ? "demo" : "com.mattiacolombo.Beep"))
            _session = State(initialValue: session)
            _sync = State(initialValue: SyncEngine(context: container.mainContext))
            if DemoData.isEnabled {
                try DemoData.seed(into: container.mainContext)
                session.enterDemo()
            }
        } catch {
            fatalError("Cannot open the local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(sync)
                .environment(opener)
                .task { if !DemoData.isEnabled { session.restore() } }
        }
        .modelContainer(container)
    }
}
