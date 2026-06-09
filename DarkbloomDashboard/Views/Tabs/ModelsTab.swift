import SwiftUI
import FiveKit

struct ModelsTab: View {
    @Environment(APIDataController.self) private var dataController
    
    func huggingFaceSearchUrl(for id: String) -> URL {
        let baseUrl = URL(string: "https://huggingface.co/models")!
        return baseUrl.appending(queryItems: [
            URLQueryItem(name: "sort", value: "trending"),
            URLQueryItem(name: "search", value: id)
        ])
    }
    
    var body: some View {
        Form {
            ForEach(dataController.models ?? []) { model in
                Section {
                    LabeledContent {
                        Text(model.contextLength, format: .number.notation(.compactName))
                    } label: {
                        Text("Context Length")
                    }
                    LabeledContent {
                        Text(model.maxOutputLength, format: .number.notation(.compactName))
                    } label: {
                        Text("Max Output Tokens")
                    }
                    LabeledContent {
                        Text(model.metadata.routableProviders, format: .number.notation(.compactName))
                    } label: {
                        Text("Routable Provider Count")
                    }
                    LabeledContent {
                        HStack {
                            let multiplier: Decimal = 1_000_000
                            VStack(alignment: .leading) {
                                let value: Decimal = Decimal(string: model.pricing.prompt)! * multiplier
                                Text("Input")
                                    .foregroundStyle(.secondary)
                                Text(value, format: .currency(code: "USD"))
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                Text("/M tokens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 8)
                            .padding(.trailing, 24)
                            
                            VStack(alignment: .leading) {
                                let value: Decimal = Decimal(string: model.pricing.completion)! * multiplier
                                Text("Output")
                                    .foregroundStyle(.secondary)
                                Text(value, format: .currency(code: "USD"))
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                Text("/M tokens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 8)
                            .padding(.trailing, 24)
                        }
                    } label: {
                        Text("Pricing")
                    }
                } header: {
                    HStack {
                        Text(model.metadata.displayName)
                        Spacer()
                        Link(destination: huggingFaceSearchUrl(for: model.huggingFaceId)) {
                            Image("huggingface")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

#Preview(traits: .controllers) {
    ModelsTab()
}
