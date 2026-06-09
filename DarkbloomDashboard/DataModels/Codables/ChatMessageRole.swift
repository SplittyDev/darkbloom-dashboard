import Foundation
import OpenAI

nonisolated enum ChatMessageRole: String, Sendable {
    case system = "system"
    case assistant = "assistant"
    case developer = "developer"
    case user = "user"
    case tool = "tool"
}

extension ChatMessageRole {
    
    init(from role: OpenAI::ChatQuery.ChatCompletionMessageParam.Role) {
        self.init(rawValue: role.rawValue)!
    }
    
    /// The equivalent role in the `OpenAI` package.
    var openAI: OpenAI::ChatQuery.ChatCompletionMessageParam.Role {
        switch self {
            case .system: .system
            case .assistant: .assistant
            case .developer: .developer
            case .user: .user
            case .tool: .tool
        }
    }
}
