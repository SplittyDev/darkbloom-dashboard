import SwiftUI

struct MachineListTab: View {
    private let settings = Settings.shared
    private let fleet = FleetController.shared
    
    var body: some View {
        List {
            ForEach(fleet.machines) { machine in
                NavigationLink(value: machine) {
                    Text(machine.serialNo)
                }
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
