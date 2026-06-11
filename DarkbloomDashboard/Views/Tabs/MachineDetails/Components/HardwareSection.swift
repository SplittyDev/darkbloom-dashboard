import SwiftUI

extension MachineDetailTab {
    struct HardwareSection: View {
        let hardware: MachineHardwareInfo
        
        var body: some View {
            Section {
                LabeledContent {
                    Text(hardware.modelDisplayName)
                } label: {
                    Text("Model")
                }
                LabeledContent {
                    Text("\(hardware.memoryGb) GB")
                } label: {
                    Text("Unified Memory")
                }
                LabeledContent {
                    Text("\(hardware.memoryBandwidthGbs) GB/s")
                } label: {
                    Text("Memory Bandwidth")
                }
            } header: {
                Text("Hardware")
            }
        }
    }
}
