import SwiftUI

/// Keyboard commands: the iPadOS menu bar and ⌘-hold overlay, and the Mac menu bar.
struct BeepCommands: Commands {
    let session: AppSession
    let sync: SyncEngine
    let router: AppRouter

    var body: some Commands {
        #if os(iOS)
        // The Mac app has a real Settings scene, which owns ⌘, already.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { router.showSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }
        #endif
        CommandMenu("WeBeep") {
            Button("Sync Now") {
                guard let client = session.client, let user = session.user else { return }
                Task { _ = await sync.syncAll(client: client, userID: user.id) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(sync.isRunning || session.client == nil)
            Button("Search") { router.selectedTab = .search }
                .keyboardShortcut("f", modifiers: .command)
            Button("Notifications") { router.showNotifications = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Courses") { router.selectedTab = .courses }
                .keyboardShortcut("1", modifiers: .command)
            Button("Recent") { router.selectedTab = .recent }
                .keyboardShortcut("2", modifiers: .command)
            Button("Activity") { router.selectedTab = .activity }
                .keyboardShortcut("3", modifiers: .command)
        }
    }
}
