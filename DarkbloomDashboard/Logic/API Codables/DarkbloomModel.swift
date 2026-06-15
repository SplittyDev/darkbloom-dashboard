import Foundation

nonisolated enum DarkbloomModel: Equatable, Hashable {
    case `gemma-4-26b`
    case `gemma-4-26b-8bit`
    case `gpt-oss-20b`
    case `legacy-gemma-4-26b-a4b-it-8bit`
    case `legacy-qwen3.5-122b-a10b-8bit`
    case unknown(String)
}

nonisolated extension DarkbloomModel: Identifiable {
    var id: String {
        rawValue
    }
}

nonisolated extension DarkbloomModel: RawRepresentable<String> {
    init(rawValue: String) {
        self = switch rawValue {
            // Current models
            case "gemma-4-26b": .`gemma-4-26b`
            case "gpt-oss-20b": .`gpt-oss-20b`
            // Legacy models
            case "mlx-community/gemma-4-26b-a4b-it-8bit": .`legacy-gemma-4-26b-a4b-it-8bit`
            case "mlx-community/Qwen3.5-122B-A10B-8bit": .`legacy-qwen3.5-122b-a10b-8bit`
            // Unknown models
            case let other: .unknown(other)
        }
    }
    
    var rawValue: String {
        switch self {
            case .`gemma-4-26b`: "gemma-4-26b"
            case .`gemma-4-26b-8bit`: "gemma-4-26b-8bit"
            case .`gpt-oss-20b`: "gpt-oss-20b"
            case .`legacy-gemma-4-26b-a4b-it-8bit`: "mlx-community/gemma-4-26b-a4b-it-8bit"
            case .`legacy-qwen3.5-122b-a10b-8bit`: "mlx-community/qwen3.5-122b-a10b-8bit"
            case .unknown(let id): id
        }
    }
}

nonisolated extension DarkbloomModel: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let modelName = try container.decode(String.self)
        self.init(rawValue: modelName)
    }
}

nonisolated extension DarkbloomModel {
    static var recommendedCases: [DarkbloomModel] {
        [.`gemma-4-26b`, .`gpt-oss-20b`]
    }
    
    var displayName: String {
        switch self {
            case .`gemma-4-26b`: "Gemma 4 26B"
            case .`gemma-4-26b-8bit`: "Gemma 4 26B 8-bit (rollback)"
            case .`gpt-oss-20b`: "GPT-OSS 20B"
            case .`legacy-gemma-4-26b-a4b-it-8bit`: "Gemma 4 26B A4B"
            case .`legacy-qwen3.5-122b-a10b-8bit`: "Qwen3.5 122B A10B"
            case .unknown(let string): string
        }
    }
}
