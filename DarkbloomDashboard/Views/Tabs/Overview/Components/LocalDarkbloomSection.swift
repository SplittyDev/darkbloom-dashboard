#if os(macOS)

import SwiftUI
import FiveKit

extension OverviewTab {
    struct LocalDarkbloomSection: View {
        @Environment(APIDataController.self) private var dataController
        @Environment(LocalServiceController.self) private var localServiceController
        
        private let settings = Settings.shared
        
        var body: some View {
            Section {
                if let version = localServiceController.darkbloomVersion {
                    LabeledContent {
                        Text(version)
                    } label: {
                        Text("Version")
                    }
                }
            } header: {
                HStack(alignment: .bottom) {
                    Label("Local Service", systemImage: "apple.terminal")
                    Spacer()
                    if let isRunning = localServiceController.processIsRunning {
                        Text(isRunning ? "Running" : "Stopped")
                            .foregroundStyle(isRunning ? Color.secondary : Color.red)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
    }
}

#endif
