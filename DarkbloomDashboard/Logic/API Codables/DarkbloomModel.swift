import Foundation

enum DarkbloomModel: Equatable, Hashable {
    case `qwen3.6-35b-a3b-vl-mtp-mxfp8`
    case `qwen3.5-35b-a3b`
    case `qwen3-vl-30b-a3b-instruct`
    case `gemma-4-26b`
    case `gemma-4-26b-8bit`
    case `gemma-4-26b-qat-4bit`
    case `gpt-oss-20b`
    case `legacy-gemma-4-26b-a4b-it-8bit`
    case `legacy-qwen3.5-122b-a10b-8bit`
    case unknown(String)
}

extension DarkbloomModel: Identifiable {
    var id: String {
        rawValue
    }
}

extension DarkbloomModel: CaseIterable {
    static var allCases: [DarkbloomModel] {
        [
            .`qwen3.6-35b-a3b-vl-mtp-mxfp8`,
            .`qwen3.5-35b-a3b`,
            .`qwen3-vl-30b-a3b-instruct`,
            .`gemma-4-26b`,
            .`gemma-4-26b-8bit`,
            .`gemma-4-26b-qat-4bit`,
            .`gpt-oss-20b`,
            .`legacy-gemma-4-26b-a4b-it-8bit`,
            .`legacy-qwen3.5-122b-a10b-8bit`,
        ]
    }
}

extension DarkbloomModel: RawRepresentable<String> {
    init(rawValue: String) {
        for model in Self.allCases where model.rawValue == rawValue {
            self = model
            return
        }
        self = .unknown(rawValue)
    }
    
    var rawValue: String {
        switch self {
            case .`qwen3.6-35b-a3b-vl-mtp-mxfp8`: "qwen3.6-35b-a3b-vl-mtp-mxfp8"
            case .`qwen3.5-35b-a3b`: "qwen3.5-35b-a3b"
            case .`qwen3-vl-30b-a3b-instruct`: "qwen3-vl-30b-a3b-instruct"
            case .`gemma-4-26b`: "gemma-4-26b"
            case .`gemma-4-26b-8bit`: "gemma-4-26b-8bit"
            case .`gemma-4-26b-qat-4bit`: "gemma-4-26b-qat-4bit"
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
        self.init(rawValue: modelName)
    }
}

extension DarkbloomModel {
    static var recommendedCases: [DarkbloomModel] {
        [
            .`qwen3.6-35b-a3b-vl-mtp-mxfp8`,
            .`qwen3.5-35b-a3b`,
            .`qwen3-vl-30b-a3b-instruct`,
            .`gemma-4-26b`,
            .`gpt-oss-20b`
        ]
    }
    
    var displayName: String {
        switch self {
            case .`qwen3.6-35b-a3b-vl-mtp-mxfp8`: "Qwen3.6 35B A3B"
            case .`qwen3.5-35b-a3b`: "Qwen3.5 35B A3B"
            case .`qwen3-vl-30b-a3b-instruct`: "Qwen3 VL 30B A3B Instruct"
            case .`gemma-4-26b`: "Gemma 4 26B"
            case .`gemma-4-26b-8bit`: "Gemma 4 26B 8-bit (rollback)"
            case .`gemma-4-26b-qat-4bit`: "Gemma 4 26B QAT 4-bit"
            case .`gpt-oss-20b`: "GPT-OSS 20B"
            case .`legacy-gemma-4-26b-a4b-it-8bit`: "Gemma 4 26B A4B"
            case .`legacy-qwen3.5-122b-a10b-8bit`: "Qwen3.5 122B A10B"
            case .unknown(let string): string
        }
    }
}
