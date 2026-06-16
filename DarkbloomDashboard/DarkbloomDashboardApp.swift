import SwiftUI
import SwiftData

enum SwiftDataUtils {
    static let schema = Schema([
        ChatModel.self,
        ChatMessageModel.self,
        MachineModel.self,
        AccountBalanceModel.self,
    ])
    
    static var activeModelContainer: ModelContainer {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            previewModelContainer
        } else {
            sharedModelContainer
        }
    }
    
    private static var sharedModelContainer: ModelContainer = {
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    private static var previewModelContainer: ModelContainer = {
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    /// Creates a background `ModelContext` with autosave disabled.
    static var backgroundContext: ModelContext {
        let context = ModelContext(activeModelContainer)
        context.autosaveEnabled = false
        return context
    }
}

@main
struct Darkbloom_DashboardApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(SwiftDataUtils.activeModelContainer)
    }
}
