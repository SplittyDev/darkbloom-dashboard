import SwiftUI
import FiveKit

extension OverviewTab {
    struct TrackedMachineListSection: View {
        @Environment(APIDataController.self) private var viewModel
        
        @State private var showAddMachineAlert: Bool = false
        @State private var newMachineSerialNumber: String = ""
        
        private let settings = Settings.shared
        
        var body: some View {
            Section {
                if settings.trackedMachineSerialNumbers.isEmpty {
                    Text("You haven't tracked any machines yet.")
                } else {
                    ForEach(settings.trackedMachineSerialNumbers) { serialNo in
                        HStack(alignment: .firstTextBaseline) {
                            Text(serialNo)
                            Spacer()
                            if let machine = viewModel.machineInfo[serialNo] {
                                TrustExplanationButton(trust: machine.trust)
                            }
                        }
                        .contentShape(.rect)
                        .contextMenu {
                            if #available(iOS 26, macOS 26, *) {
                                Button(role: .destructive) {
                                    settings.trackedMachineSerialNumbers.removeAll(subject: serialNo)
                                }
                            } else {
                                Button("Delete", role: .destructive) {
                                    settings.trackedMachineSerialNumbers.removeAll(subject: serialNo)
                                }
                            }
                        }
                    }
                    .onDelete { indexSet in
                        settings.trackedMachineSerialNumbers.remove(atOffsets: indexSet)
                    }
                }
            } header: {
                HStack(alignment: .bottom) {
                    Label("Fleet", systemImage: "server.rack")
                    Spacer()
                    Button {
                        showAddMachineAlert = true
                    } label: {
                        Text("Add Machine")
                    }
                }
            }
            .alert("Add Machine", isPresented: $showAddMachineAlert) {
                TextField("Serial Number", text: $newMachineSerialNumber)
                
                Button("Save") {
                    settings.trackedMachineSerialNumbers.append(newMachineSerialNumber)
                    newMachineSerialNumber = ""
                }
                
                if #available(iOS 26, macOS 26, *) {
                    Button(role: .cancel) {
                        newMachineSerialNumber = ""
                    }
                } else {
                    Button("Cancel", role: .cancel) {
                        newMachineSerialNumber = ""
                    }
                }
            }
        }
    }
}

#Preview {
    Form {
        OverviewTab.TrackedMachineListSection()
            .environment(APIDataController())
    }
    .formStyle(.grouped)
}
