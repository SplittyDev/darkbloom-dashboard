import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \MachineModel.serialNo) private var machines: [MachineModel]
    @Query(sort: \AccountBalanceModel.createdAt) private var accountBalances: [AccountBalanceModel]
    
    private let dataController = APIDataController.shared
    private let fleetController = FleetController.shared
    private let earningsController = EarningsController.shared
    private let uiPreferenceController = UIPreferenceController.shared
    
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
        .environment(fleetController)
        .environment(earningsController)
        .environment(uiPreferenceController)
        .redacted(reason: uiPreferenceController.usesPrivacyMode ? .privacy : [])
    }
    
    var body: some View {
        platformContent
            .onAppear {
                Migrator(modelContext: modelContext).run()
            }
            .onChange(of: accountBalances) {
                print("Balances: \(accountBalances.count)")
                earningsController.calculateProjections(basedOn: accountBalances)
            }
            .onChange(of: machines, initial: true) {
                fleetController.updateMachines(machines)
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
