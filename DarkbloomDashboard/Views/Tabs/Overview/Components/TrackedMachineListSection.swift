import SwiftUI
import SwiftData
import FiveKit

extension OverviewTab {
    struct TrackedMachineListSection: View {
        @Environment(\.modelContext) private var modelContext
        
        @Environment(APIDataController.self) private var dataController
        @Environment(FleetController.self) private var fleetController
        
        private let settings = Settings.shared
        
        var body: some View {
            Section {
                if fleetController.machines.isEmpty {
                    Text("You haven't tracked any machines yet.")
                } else {
                    ForEach(fleetController.machines) { machine in
                        HStack(alignment: .firstTextBaseline) {
                            Text(machine.serialNo)
                            Spacer()
                            if let machine = dataController.machineInfo[machine.serialNo] {
                                TrustExplanationButton(trust: machine.trust)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let machine = fleetController.machines[index]
                            modelContext.delete(machine)
                        }
                    }
                }
            } header: {
                HStack(alignment: .bottom) {
                    Label("Fleet", systemImage: "server.rack")
                    Spacer()
                }
            }
        }
    }
}

#Preview(traits: .controllers) {
    Form {
        OverviewTab.TrackedMachineListSection()
    }
    .formStyle(.grouped)
}
