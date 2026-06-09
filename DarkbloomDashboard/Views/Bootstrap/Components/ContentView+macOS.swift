#if os(macOS)

import SwiftUI
import SwiftData

struct ContentView_macOS: View {
    @Environment(APIDataController.self) private var dataController
    @Environment(LocalLogController.self) private var logsViewModel
    @Environment(LocalServiceController.self) private var localServiceController
    
    @Query(sort: \ChatModel.updatedAt, order: .reverse) private var chats: [ChatModel]
    
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
            case .logs:
                return "Last updated: \(dateFormatter.string(from: logsViewModel.lastFetchDate))"
            case .chat, .chats:
                return ""
        }
    }
    
    private func requestUpdate(for tab: SidebarTab) {
        switch tab {
            case .overview, .network, .machine, .machines, .loadGenerator:
                dataController.updateStatsAndAttestations()
                dataController.updateBalance()
            case .models:
                dataController.updateModels()
            case .logs, .chat, .chats:
                break // not supported
        }
    }
    
    private func isUpdating(for tab: SidebarTab) -> Bool {
        switch tab {
            case .overview, .network, .machine, .machines, .loadGenerator:
                dataController.isUpdatingStats
            case .models:
                dataController.isUpdatingModels
            case .logs:
                logsViewModel.isUpdating
            case .chat, .chats:
                false
        }
    }
    
    private func shouldShowUpdateButton(for tab: SidebarTab) -> Bool {
        switch tab {
            case .overview, .network, .models, .machine, .machines:
                true
            case .loadGenerator, .logs, .chat, .chats:
                false
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.activeTab) {
                Section {
                    SidebarLink(value: .overview)
                } header: {
                    Text("Account")
                }
                
                Section {
                    SidebarLink(value: .network)
                    SidebarLink(value: .models)
                } header: {
                    Text("Darkbloom")
                }
                    
                if !settings.trackedMachineSerialNumbers.isEmpty {
                    Section {
                        ForEach(settings.trackedMachineSerialNumbers) { serialNo in
                            SidebarMachineLink(serialNo: serialNo)
                        }
                    } header: {
                        Text("Fleet")
                    }
                }
                
                Section {
                    SidebarLoadTestingLink()
                    SidebarLink(value: .logs, badge: logsViewModel.unseenLogCount)
                } header: {
                    Text("Utilities")
                }
                
                Section {
                    ForEach(chats) { chat in
                        SidebarChatLink(chat: chat)
                    }
                    Button {
                        navigation.activeTab = .chat(nil)
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                } header: {
                    Text("Chats")
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
                    case .machine(let serialNo):
                        MachineDetailTab(serialNo: serialNo)
                    case .machines:
                        EmptyView() // not supported on macOS
                    case .chat(let chatId):
                        if let chatId {
                            ChatDetailTab(chatId: chatId).id(chatId)
                        } else {
                            ChatDetailTab()
                        }
                    case .chats:
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
