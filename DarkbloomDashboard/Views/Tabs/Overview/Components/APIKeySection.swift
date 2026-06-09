import SwiftUI
import FiveKit

extension OverviewTab {
    struct APIKeySection: View {
        @AppStorage("darkbloom_api_key_locked") private var apiKeyLocked: Bool = false
        @Bindable private var settings = Settings.shared
        
        var body: some View {
            Section {
                LabeledContent {
                    HStack(alignment: .firstTextBaseline) {
                        if apiKeyLocked {
                            Text("Hidden")
                                .foregroundStyle(.secondary)
                        } else {
                            SecureField("API Key", text: $settings.apiKey ?? "")
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                        }
                        
                        Button {
                            apiKeyLocked.toggle()
                        } label: {
                            if apiKeyLocked {
                                Text("Edit")
                            } else {
                                Text("Save")
                            }
                        }
                    }
                } label: {
                    Text("API Key")
                }
            } footer: {
                if settings.apiKey == nil || settings.apiKey?.isEmpty == true {
                    Link(
                        "Get your API key here",
                        destination: URL(string: "https://console.darkbloom.dev/api-console")!
                    )
                }
            }
        }
    }
}

#Preview(traits: .controllers) {
    Form {
        OverviewTab.APIKeySection()
    }
    .formStyle(.grouped)
}
