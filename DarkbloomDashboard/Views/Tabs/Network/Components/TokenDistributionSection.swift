import SwiftUI
import FiveKit

extension NetworkTab {
    struct TokenDistributionSection: View {
        let stats: DarkbloomStats
        
        var body: some View {
            Section {
                GeometryReader { proxy in
                    let inPercentage = CGFloat(stats.totalPromptTokens) / CGFloat(stats.totalTokens)
                    let outPercentage = CGFloat(stats.totalCompletionTokens) / CGFloat(stats.totalTokens)
                    
                    HStack(spacing: 0) {
                        Color.accent
                            .frame(width: proxy.size.width * inPercentage)
                            .contrast(0.5)
                            .overlay {
                                Text(stats.totalPromptTokens, format: .number.notation(.compactName))
                                + Text(" in")
                            }
                        Color.green
                            .frame(width: proxy.size.width * outPercentage)
                            .contrast(0.5)
                            .overlay {
                                Text(stats.totalCompletionTokens, format: .number.notation(.compactName))
                                + Text(" out")
                            }
                    }
                    .clipShape(.rect(cornerRadius: 8))
                }
                .frame(height: 32)
            } header: {
                Text("Token Distribution")
            }
        }
    }
}

#Preview(traits: .controllers) {
    @Previewable @Environment(APIDataController.self) var dataController
    
    Form {
        if let stats = dataController.stats {
            NetworkTab.TokenDistributionSection(stats: stats)
        }
    }
    .formStyle(.grouped)
}
