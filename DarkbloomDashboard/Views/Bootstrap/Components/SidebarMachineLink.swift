import SwiftUI
import FiveKit

struct SidebarMachineLink: View {
    @Environment(APIDataController.self) private var viewModel
    
    let serialNo: String
    
    var machine: MachineInfo? {
        viewModel.machineInfo[serialNo]
    }
    
    var body: some View {
        let value = SidebarTab.machine(serialNo)
        NavigationLink(value: value) {
            HStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.systemFill)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Group {
                            if let machine, let model = ModelIdentifier(rawValue: machine.hardware.modelIdentifier) {
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
                    if let machine {
                        Text(machine.hardware.modelDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.blurReplace)
                    }
                }
                Spacer()
                if let machine {
                    if machine.trust.isOnline {
                        Group {
                            if machine.trust.isTrusted {
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
        .animation(.smooth, value: machine)
    }
}

#Preview(traits: .controllers) {
    List {
        SidebarMachineLink(serialNo: "NJD6MGW279")
    }
    .listStyle(.sidebar)
}
