import Foundation
import SwiftData

@MainActor
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
        do {
            #if os(macOS)
            let storeURL: URL = try {
                let appSupportURL = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first!
                let appDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true)
                try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
                return appDirectory.appendingPathComponent("default.store")
            }()
            let modelConfiguration = ModelConfiguration(schema: schema, url: storeURL)
            #else
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            #endif
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    private static var previewModelContainer: ModelContainer = {
        do {
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
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
