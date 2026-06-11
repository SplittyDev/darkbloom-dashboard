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
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.systemFill)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Group {
                            if let info = machine.currentInfo, let model = ModelIdentifier(rawValue: info.hardware.modelIdentifier) {
                                Image(systemName: model.modelKind.systemImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(6)
                            } else {
                                Image(systemName: value.systemImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .padding(6)
                            }
                        }
                        .transition(.blurReplace)
                    }
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
                if let info = machine.currentInfo {
                    if info.trust.isOnline {
                        Group {
                            if info.trust.isTrusted {
                                Text(Image(systemName: "checkmark.shield.fill"))
                            } else {
                                Text(Image(systemName: "shield.slash.fill"))
                                    .foregroundStyle(Color.yellow)
                            }
                        }
                        .transition(.blurReplace)
                    } else {
                        Text(Image(systemName: "circle.fill"))
                            .foregroundStyle(Color.red)
                            .transition(.blurReplace)
                    }
                }
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
