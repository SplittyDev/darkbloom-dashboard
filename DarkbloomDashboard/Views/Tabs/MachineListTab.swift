import SwiftUI
import SwiftData

struct MachineListTab: View {
    @Environment(\.modelContext) private var modelContext
    
    private let settings = Settings.shared
    private let fleet = FleetController.shared
    
    var body: some View {
        List {
            ForEach(fleet.machines) { machine in
                NavigationLink(value: machine) {
                    HStack {
                        MachineHardwareIcon(machine: machine, size: 28)
                        VStack(alignment: .leading) {
                            Text(machine.serialNo)
                                .privacySensitive()
                            if let info = machine.currentInfo {
                                Text(info.hardware.modelDisplayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .transition(.blurReplace)
                            }
                        }
                        Spacer()
                        CompactTrustIndicator(machine: machine)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let machine = fleet.machines[index]
                    modelContext.delete(machine)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddFleetMachineButton()
            }
        }
        .navigationDestination(for: MachineModel.self) { machine in
            MachineDetailTab(machine: machine)
                .navigationTitle(machine.serialNo)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
    }
}

#Preview(traits: .controllers) {
    NavigationStack {
        MachineListTab()
    }
}
