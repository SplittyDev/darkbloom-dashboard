import SwiftUI
import SwiftData
import FiveKit

struct SidebarMachineLink: View {
    @Environment(\.modelContext) private var modelContext
    
    @Environment(APIDataController.self) private var viewModel
    
    let machine: MachineModel
    
    var body: some View {
        let value = SidebarTab.machine(machine)
        NavigationLink(value: value) {
            HStack {
                MachineHardwareIcon(machine: machine, size: 28)
                VStack(alignment: .leading) {
                    Text(value.title)
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
        .contextMenu {
            DeleteButton {
                modelContext.delete(machine)
            }
        }
        .animation(.smooth, value: machine)
    }
}

#Preview(traits: .controllers) {
    List {
        SidebarMachineLink(machine: MachineModel(serialNo: "NJD6MGW279"))
    }
    .listStyle(.sidebar)
}
