import SwiftUI
import FiveKit

extension NetworkTab {
    struct NetworkStatsSection: View {
        @Environment(APIDataController.self) private var dataController
        
        let stats: DarkbloomStats
        
        var body: some View {
            Section {
                LabeledContent {
                    Text(stats.totalTokens, format: .number.notation(.compactName))
                } label: {
                    Text("Tokens Served")
                }
                
                LabeledContent {
                    Text(stats.totalRequests, format: .number.notation(.compactName))
                } label: {
                    Text("Requests")
                }
                
                LabeledContent {
                    Text(stats.providers.count, format: .number.notation(.compactName))
                } label: {
                    Text("Providers Online")
                }
                
                LabeledContent {
                    let trustedProviderCount = dataController.machineInfo.values.count(where: \.trust.isTrusted)
                    Text(trustedProviderCount, format: .number.notation(.compactName))
                } label: {
                    Text("Providers Trusted")
                }
            } header: {
                Text("Network Statistics")
            }
        }
    }
}

#Preview(traits: .controllers) {
    @Previewable @Environment(APIDataController.self) var dataController
    
    Form {
        if let stats = dataController.stats {
            NetworkTab.NetworkStatsSection(stats: stats)
        }
    }
    .formStyle(.grouped)
}
