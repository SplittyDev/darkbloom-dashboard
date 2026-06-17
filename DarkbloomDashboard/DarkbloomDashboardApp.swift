import SwiftUI
import SwiftData

@main
struct Darkbloom_DashboardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(SwiftDataUtils.activeModelContainer)
    }
}
