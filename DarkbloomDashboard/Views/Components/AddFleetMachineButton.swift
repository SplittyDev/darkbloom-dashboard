import SwiftUI
import SwiftData

struct AddFleetMachineButton: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var showAddMachineAlert: Bool = false
    @State private var newMachineSerialNumber: String = ""
    
    var body: some View {
        Button {
            showAddMachineAlert = true
        } label: {
            Text(Image(systemName: "plus"))
        }
        #if os(macOS)
        .buttonStyle(.accessoryBar)
        .buttonBorderShape(.circle)
        #endif
        .alert("Add Machine", isPresented: $showAddMachineAlert) {
            TextField("Serial Number", text: $newMachineSerialNumber)
            
            Button("Save") {
                let model = MachineModel(serialNo: newMachineSerialNumber)
                modelContext.insert(model)
                newMachineSerialNumber = ""
            }
            
            CancelButton {
                newMachineSerialNumber = ""
            }
        }
    }
}
