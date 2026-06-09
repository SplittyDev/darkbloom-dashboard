#if os(macOS)

import SwiftUI
import FiveKit

struct LoadGeneratorTab: View {
    @Environment(LoadTestingController.self) private var loadTest
    
    @State private var showApiKeyPrompt: Bool = false
    @State private var newApiKey: String = ""
    
    private let settings = Settings.shared
    
    func obfuscateApiKey(_ key: String) -> String {
        let count = key.count
        let rawCount = count / 4
        let rawPrefix = key.prefix(rawCount)
        let rawSuffix = key.suffix(rawCount)
        let obfuscatedMiddle = String(Array(repeating: "*", count: count - rawCount * 2))
        return "\(rawPrefix)\(obfuscatedMiddle)\(rawSuffix)"
    }
    
    var body: some View {
        @Bindable var loadTest = self.loadTest
        
        Form {
            Section {
                ForEach(settings.loadTestingApiKeys, id: \.self) { apiKey in
                    Text(obfuscateApiKey(apiKey))
                        .monospaced()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                        .contextMenu {
                            DeleteButton {
                                settings.loadTestingApiKeys.removeAll(subject: apiKey)
                            }
                        }
                }
                .onDelete { indexSet in
                    settings.loadTestingApiKeys.remove(atOffsets: indexSet)
                }
            } header: {
                HStack {
                    Text("API Keys")
                    Spacer()
                    Button {
                        showApiKeyPrompt = true
                    } label: {
                        Text(Image(systemName: "plus"))
                    }
                }
            } footer: {
                Text("Rate limits are per-account. Add API keys from multiple accounts.")
            }
            .alert("Add Account", isPresented: $showApiKeyPrompt) {
                TextField("API Key", text: $newApiKey)
                
                Button("Save") {
                    settings.loadTestingApiKeys.append(newApiKey)
                    newApiKey = ""
                }
                
                if #available(iOS 26, macOS 26, *) {
                    Button(role: .cancel) {
                        newApiKey = ""
                    }
                } else {
                    Button("Cancel", role: .cancel) {
                        newApiKey = ""
                    }
                }
            }
            
            Section {
                HStack {
                    TextField("Requests", value: $loadTest.requestsToSend, format: .number)
                    
                    Button {
                        Task {
                            try? await loadTest.run(
                                apiKeys: settings.loadTestingApiKeys,
                                payload: "Hello.",
                                maxConcurrency: 3,
                                minDelay: 3
                            )
                        }
                    } label: {
                        Text("Run (Small Payload)")
                    }
                    .disabled(loadTest.inProgress || settings.loadTestingApiKeys.isEmpty)
                    
                    Button {
                        Task {
                            try? await loadTest.run(
                                apiKeys: settings.loadTestingApiKeys,
                                payload: "Tell me a fantasy story with at least 200 words.",
                                maxConcurrency: 20,
                                minDelay: 0
                            )
                        }
                    } label: {
                        Text("Run (Large Payload)")
                    }
                    .disabled(loadTest.inProgress || settings.loadTestingApiKeys.isEmpty)
                }
                
                HStack {
                    if loadTest.inProgress {
                        ProgressView().controlSize(.small)
                    }
                    
                    Spacer()
                    
                    LabeledPill {
                        Text(loadTest.requestsInFlight, format: .number)
                    } label: {
                        Text("Inflight")
                    }
                    
                    LabeledPill(.positive) {
                        Text(loadTest.requestsDone, format: .number)
                    } label: {
                        Text("Succeeded")
                    }
                    
                    LabeledPill(.negative) {
                        Text(loadTest.requestsFailed, format: .number)
                    } label: {
                        Text("Failed")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    LoadGeneratorTab()
        .environment(LoadTestingController())
}

#endif
