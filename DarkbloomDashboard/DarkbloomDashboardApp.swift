import SwiftUI
import SwiftData

@main
struct Darkbloom_DashboardApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AutopilotAppDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(SwiftDataUtils.activeModelContainer)
    }
}

#if os(macOS)
@MainActor
final class AutopilotAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let autopilot = AutopilotController.shared
        guard !autopilot.canEnable else { return .terminateNow }
        // Let an in-flight drain finish, or restore serving after a paused calibration.
        Task {
            await autopilot.pauseAndWait()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
