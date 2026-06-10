import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    private let dataController = APIDataController.shared
    private let earningsController = EarningsController.shared
    
    #if os(macOS)
    private let localServiceController = LocalServiceController.shared
    private let loadTestingController = LoadTestingController.shared
    private let localLogController = LocalLogController.shared
    private let restartController = RestartController.shared
    #endif
    
    private let settings = Settings.shared
    
    private func performMigrations() {
        func createAndDeduplicateStableChatModelIDs() {
            let fdChats = FetchDescriptor(predicate: Predicate<ChatModel>.true)
            let fdChatResults = try? modelContext.fetch(fdChats)
            var stableIdSet: Set<String> = []
            for chatModel in fdChatResults ?? [] {
                var createNew: Bool = false
                if let stableId = chatModel._stableId {
                    if stableIdSet.contains(stableId) {
                        createNew = true
                    } else {
                        stableIdSet.insert(stableId)
                    }
                } else {
                    createNew = true
                }
                if createNew {
                    let newStableId = UUID().uuidString
                    chatModel._stableId = newStableId
                    stableIdSet.insert(newStableId)
                }
            }
            try? modelContext.save()
        }
        createAndDeduplicateStableChatModelIDs()
    }
    
    @ViewBuilder private var platformContent: some View {
        Group {
            #if os(macOS)
            ContentView_macOS()
                .environment(localServiceController)
                .environment(loadTestingController)
                .environment(localLogController)
                .environment(restartController)
            #elseif os(iOS)
            ContentView_iOS()
            #else
            #error("Unsupported platform.")
            #endif
        }
        .environment(dataController)
        .environment(earningsController)
    }
    
    var body: some View {
        platformContent
            .onAppear {
                performMigrations()
            }
            .task(id: dataController.balanceChanges) {
                await earningsController.calculateProjections(basedOn: dataController.balanceChanges)
            }
            .onChange(of: settings.apiKey) {
                guard let apiKey = settings.apiKey else { return }
                Task {
                    do {
                        try await dataController.update(apiKey: apiKey)
                    } catch {
                        print(error)
                    }
                }
            }
    }
}

#Preview {
    ContentView()
}
