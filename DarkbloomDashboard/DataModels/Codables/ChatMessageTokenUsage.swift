import Foundation

nonisolated struct ChatMessageTokenUsage: Codable, Equatable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

nonisolated extension ChatMessageTokenUsage {
    var data: Data? {
        try? JSONEncoder().encode(self)
    }
    
    init?(from data: Data) {
        if let _self = try? JSONDecoder().decode(Self.self, from: data) {
            self = _self
        } else {
            return nil
        }
    }
}
