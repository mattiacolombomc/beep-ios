import SwiftUI

struct MainTabs: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        TabView {
            Tab("Courses", systemImage: "graduationcap") {
                NavigationStack {
                    ContentUnavailableView("Courses", systemImage: "graduationcap", description: Text(session.user?.fullname ?? ""))
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right") { session.signOut() }
                            }
                        }
                }
            }
        }
    }
}
