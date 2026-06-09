import Foundation
import SwiftData

@Model
final class ChatMessageModel {
    var createdAt: Date = Date.now
    var chat: ChatModel?
    
    private var _role: String
    var role: ChatMessageRole {
        get { ChatMessageRole(rawValue: _role)! }
        set { _role = newValue.rawValue }
    }
    
    private var _usage: Data?
    var usage: ChatMessageTokenUsage? {
        get { _usage.flatMap(ChatMessageTokenUsage.init(from:)) }
        set { _usage = newValue?.data }
    }
    
    var content: String
    
    init(chat: ChatModel? = nil, role: ChatMessageRole, content: String) {
        self.chat = chat
        self._role = role.rawValue
        self.content = content
    }
}
