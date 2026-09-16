import SwiftData
import SwiftUI

@main
struct BeepApp: App {
    @State private var session = AppSession()
    private let container: ModelContainer

    init() {
        do {
            container = try StoreContainer.make()
        } catch {
            fatalError("Cannot open the local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { session.restore() }
        }
        .modelContainer(container)
    }
}
