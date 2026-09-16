import SwiftUI

/// Entry point of the UI. Will branch between onboarding and the main tabs once auth exists.
struct RootView: View {
    var body: some View {
        ContentUnavailableView(
            "Beep",
            systemImage: "graduationcap",
            description: Text("Project skeleton. Nothing to see yet.")
        )
    }
}

#Preview {
    RootView()
}
