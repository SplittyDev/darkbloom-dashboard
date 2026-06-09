#if os(iOS)

import SwiftUI

struct ContentView_iOS: View {
    @Bindable private var navigation = NavigationController.shared
    private let settings = Settings.shared
    
    var body: some View {
        TabView(selection: $navigation.activeTab) {
            Tab(
                SidebarTab.overview.title,
                systemImage: SidebarTab.overview.systemImage,
                value: .overview
            ) {
                NavigationStack {
                    OverviewTab()
                        .navigationTitle(SidebarTab.overview.title)
                }
            }
            Tab(
                SidebarTab.network.title,
                systemImage: SidebarTab.network.systemImage,
                value: .network
            ) {
                NavigationStack {
                    NetworkTab()
                        .navigationTitle(SidebarTab.network.title)
                }
            }
            Tab(
                SidebarTab.machines.title,
                systemImage: SidebarTab.machines.systemImage,
                value: .machines
            ) {
                NavigationStack {
                    MachineListTab()
                        .navigationTitle(SidebarTab.machines.title)
                }
            }
            Tab(
                SidebarTab.chats.title,
                systemImage: SidebarTab.chats.systemImage,
                value: .chats
            ) {
                NavigationStack {
                    ChatListTab()
                        .navigationTitle(SidebarTab.chats.title)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

#Preview {
    ContentView_iOS()
        .environment(APIDataController())
}

#endif
