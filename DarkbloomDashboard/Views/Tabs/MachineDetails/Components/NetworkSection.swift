import SwiftUI

extension MachineDetailTab {
    struct NetworkSection: View {
        @Environment(APIDataController.self) private var dataController
        @State private var warmupInProgress: Bool = false
        
        @Bindable var machine: MachineModel
        let activity: MachineActivityInfo
        
        var body: some View {
            Section {
                LabeledContent {
                    HStack(alignment: .bottom) {
                        ForEach(activity.models) { model in
                            Pill {
                                Text(model.displayName)
                            }
                            .controlSize(.small)
                        }
                    }
                } label: {
                    Text("Models")
                }
                LabeledContent {
                    Text(activity.requestsServed, format: .number)
                        .contentTransition(.numericText())
                } label: {
                    Text("Requests Served")
                }
                LabeledContent {
                    Text(activity.tokensGenerated, format: .number)
                        .contentTransition(.numericText())
                } label: {
                    Text("Tokens Generated")
                }
            } header: {
                Text("Network")
            } footer: {
                HStack {
                    Spacer()
                    #if os(macOS)
                    Toggle("Keep Warm", isOn: $machine.autoWarmup)
                        .toggleStyle(.checkbox)
                    #endif
                    Button {
                        warmupInProgress = true
                        Task {
                            try? await dataController.warmup(serialNumber: machine.serialNo)
                            warmupInProgress = false
                        }
                    } label: {
                        Text("Warmup")
                    }
                    .disabled(warmupInProgress)
                }
            }
            .animation(.snappy, value: activity)
        }
    }
}
