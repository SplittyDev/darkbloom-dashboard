import SwiftUI
import SwiftData

struct ContentView: View {
    private let dataController = APIDataController.shared
    private let earningsController = EarningsController.shared
    
    #if os(macOS)
    private let localServiceController = LocalServiceController.shared
    private let loadTestingController = LoadTestingController.shared
    private let localLogController = LocalLogController.shared
    private let restartController = RestartController.shared
    #endif
    
    private let settings = Settings.shared
    
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
