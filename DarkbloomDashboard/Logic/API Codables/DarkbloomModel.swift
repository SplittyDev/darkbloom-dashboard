import Foundation

enum DarkbloomModel: Equatable {
    case `gemma-4-26b`
    case `gpt-oss-20b`
    case `legacy-gemma-4-26b-a4b-it-8bit`
    case `legacy-qwen3.5-122b-a10b-8bit`
    case unknown(String)
}

extension DarkbloomModel: Identifiable {
    var id: String {
        switch self {
            case .`gemma-4-26b`: "gemma-4-26b"
            case .`gpt-oss-20b`: "gpt-oss-20b"
            case .`legacy-gemma-4-26b-a4b-it-8bit`: "mlx-community/gemma-4-26b-a4b-it-8bit"
            case .`legacy-qwen3.5-122b-a10b-8bit`: "mlx-community/qwen3.5-122b-a10b-8bit"
            case .unknown(let id): id
        }
    }
}

extension DarkbloomModel: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let modelName = try container.decode(String.self)
        self = switch modelName {
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
}

extension DarkbloomModel {
    var displayName: String {
        switch self {
            case .`gemma-4-26b`: "Gemma 4 26B"
            case .`gpt-oss-20b`: "GPT-OSS 20B"
            case .`legacy-gemma-4-26b-a4b-it-8bit`: "Gemma 4 26B A4B"
            case .`legacy-qwen3.5-122b-a10b-8bit`: "Qwen3.5 122B A10B"
            case .unknown(let string): string
        }
    }
}
