import SwiftUI

extension MachineDetailTab {
    struct NetworkSection: View {
        @Environment(APIDataController.self) private var dataController
        @State private var warmupInProgress: Bool = false
        
        let serialNo: String
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
                    Button {
                        warmupInProgress = true
                        Task {
                            try? await dataController.warmup(serialNumber: serialNo)
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
