import SwiftUI

struct MachineListTab: View {
    let settings = Settings.shared
    
    var body: some View {
        List {
            ForEach(settings.trackedMachineSerialNumbers) { serialNo in
                NavigationLink(value: serialNo) {
                    Text(serialNo)
                }
            }
        }
        .navigationDestination(for: String.self) { serialNo in
            MachineDetailTab(serialNo: serialNo)
                .navigationTitle(serialNo)
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
