import Foundation

struct ChatMessageTokenUsage: CodableData, Equatable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}
