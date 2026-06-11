import SwiftUI

struct MachineListTab: View {
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
