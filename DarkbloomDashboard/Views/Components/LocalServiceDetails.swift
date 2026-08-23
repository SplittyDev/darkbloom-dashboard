#if os(macOS)

import SwiftUI

struct LocalServiceDetails: View {
    let state: DarkbloomDaemonState
    
    var body: some View {
        LabeledContent("Version", value: state.version)
        LabeledContent(
            "Current Model",
            value: DarkbloomModel(rawValue: state.currentModel).displayName
        )
        LabeledContent {
            HStack(alignment: .bottom) {
                if state.warmModels.isEmpty {
                    Text("None")
                } else {
                    ForEach(state.warmModels.map { DarkbloomModel(rawValue: $0) }) { model in
                        Pill {
                            Text(model.displayName)
                        }
                        .controlSize(.small)
                    }
                }
            }
        } label: {
            Text("Warm Models")
        }
        LabeledContent("Inference", value: state.inferenceActive ? "Active" : "Idle")
        LabeledContent {
            HStack(alignment: .bottom) {
                Pill {
                    Text("Active ") + memory(state.capacity.gpuMemoryActiveGb)
                }
                .controlSize(.small)
                Pill {
                    Text("Cache ") + memory(state.capacity.gpuMemoryCacheGb)
                }
                .controlSize(.small)
            }
        } label: {
            Text("GPU Memory")
        }
        LabeledContent("Requests Served") {
            Text(state.stats.requestsServed, format: .number)
        }
        LabeledContent("Tokens Generated") {
            Text(state.stats.tokensGenerated, format: .number)
        }
    }
    
    private func memory(_ gigabytes: Double) -> Text {
        Text("\(gigabytes, format: .number.precision(.fractionLength(1))) GB")
    }
}

#endif
