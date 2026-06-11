#if os(macOS)

import SwiftUI
import FiveKit

extension OverviewTab {
    struct LocalDarkbloomSection: View {
        @Environment(APIDataController.self) private var dataController
        
        let localServiceController: LocalServiceController
        
        private let settings = Settings.shared
        
        private func label(for serialNumber: String) -> String {
            if serialNumber == localServiceController.currentMachineSerialNumber {
                return "This Mac (\(serialNumber))"
            }
            if let displayName = dataController.machineInfo[serialNumber]?.hardware.modelDisplayName {
                return "\(displayName) (\(serialNumber))"
            }
            return serialNumber
        }
        
        var body: some View {
            Section {
                LabeledContent {
                    if let isRunning = localServiceController.processIsRunning {
                        Text(isRunning ? "Running" : "Stopped")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                } label: {
                    Text("Process Status")
                }
                .animation(.interactiveSpring, value: localServiceController.processIsRunning)
            } header: {
                HStack(alignment: .bottom) {
                    Label("Darkbloom Process", systemImage: "apple.terminal")
                    Spacer()
                }
            }
        }
    }
}

#endif
