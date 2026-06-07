#if os(macOS)

import SwiftUI

struct ContentView_macOS: View {
    @Environment(APIDataController.self) private var dataController
    @Environment(LocalLogController.self) private var logsViewModel
    @Environment(LocalServiceController.self) private var localServiceController
    
    @Bindable private var navigation = NavigationController.shared
    private let settings = Settings.shared
    
    private func subtitle(for tab: SidebarTab) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .medium
        
        switch tab {
            case .overview, .network, .machine, .machines, .loadGenerator:
                guard let lastUpdate = dataController.lastStatUpdate else { return "" }
                return "Last updated: \(dateFormatter.string(from: lastUpdate))"
            case .models:
                guard let lastUpdate = dataController.lastModelUpdate else { return "" }
                return "Last updated: \(dateFormatter.string(from: lastUpdate))"
            case .earnings:
                guard let lastUpdate = dataController.lastBalanceUpdate else { return "" }
                return "Last updated: \(dateFormatter.string(from: lastUpdate))"
            case .logs:
                return "Last updated: \(dateFormatter.string(from: logsViewModel.lastFetchDate))"
        }
    }
    
    private func requestUpdate(for tab: SidebarTab) {
        switch tab {
            case .overview, .network, .machine, .machines, .loadGenerator:
                dataController.updateStatsAndAttestations()
            case .models:
                dataController.updateModels()
            case .earnings:
                dataController.updateBalance()
            case .logs:
                break // not supported
        }
    }
    
    private func isUpdating(for tab: SidebarTab) -> Bool {
        switch tab {
            case .overview, .network, .machine, .machines, .loadGenerator:
                dataController.isUpdatingStats
            case .models:
                dataController.isUpdatingModels
            case .earnings:
                dataController.isUpdatingBalance
            case .logs:
                logsViewModel.isUpdating
        }
    }
    
    private func shouldShowUpdateButton(for tab: SidebarTab) -> Bool {
        switch tab {
            case .overview, .network, .models, .machine, .machines, .earnings:
                true
            case .loadGenerator, .logs:
                false
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.activeTab) {
                SidebarLink(value: .overview)
                SidebarLink(value: .models)
                SidebarLink(value: .network)
                SidebarLink(value: .earnings)
                if !settings.trackedMachineSerialNumbers.isEmpty {
                    Section {
                        ForEach(settings.trackedMachineSerialNumbers) { serialNo in
                            SidebarMachineLink(serialNo: serialNo)
                        }
                    } header: {
                        Text("Machines")
                    }
                }
                Section {
                    SidebarLoadTestingLink()
                    SidebarLink(value: .logs, badge: logsViewModel.unseenLogCount)
                } header: {
                    Text("Utilities")
                }
            }
        } detail: {
            Group {
                switch navigation.activeTab {
                    case .overview:
                        OverviewTab()
                    case .network:
                        NetworkTab()
                    case .models:
                        ModelsTab()
                    case .earnings:
                        EarningsTab()
                    case .machine(let serialNo):
                        MachineDetailTab(serialNo: serialNo)
                    case .machines:
                        EmptyView() // not supported on macOS
                    case .loadGenerator:
                        LoadGeneratorTab()
                    case .logs:
                        LogsTab()
                }
            }
            .navigationTitle(navigation.activeTab.title)
            .navigationSubtitle(subtitle(for: navigation.activeTab))
            .toolbar {
                if shouldShowUpdateButton(for: navigation.activeTab) {
                    Button {
                        requestUpdate(for: navigation.activeTab)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonBorderShape(.circle)
                    .disabled(isUpdating(for: navigation.activeTab))
                }
            }
        }
        .onAppear {
            logsViewModel.startStreaming()
            localServiceController.setup()
            localServiceController.startObservation()
        }
        .onDisappear() {
            logsViewModel.stopStreaming()
            localServiceController.stopObservation()
        }
    }
}

#Preview {
    ContentView_macOS()
        .environment(APIDataController())
        .environment(LocalLogController())
}

#endif
