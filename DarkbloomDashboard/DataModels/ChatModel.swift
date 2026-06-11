import Foundation
import SwiftData

@Model
final class ChatModel {
    var _stableId: String?
    var stableId: UUID {
        if let _stableId {
            UUID(uuidString: _stableId)!
        } else {
            fatalError("ChatModel: Stable ID must be set!")
        }
    }
    
    var createdAt: Date
    var updatedAt: Date
    
    var title: String? = nil
    var isGeneratingTitle: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageModel.chat)
    var messages: [ChatMessageModel] = []
    
    private var _modelId: String?
    var model: DarkbloomModel {
        get { _modelId.flatMap(DarkbloomModel.init(rawValue:)) ?? .`gpt-oss-20b` }
        set { _modelId = newValue.rawValue }
    }
    
    private var _routing: Data?
    var routing: ChatRouting {
        get { _routing.flatMap(ChatRouting.init(from:)) ?? .auto }
        set { _routing = newValue.data }
    }
    
    init() {
        let now = Date.now
        self._stableId = UUID().uuidString
        self.createdAt = now
        self.updatedAt = now
    }
}

extension ChatModel {
    var resolvedTitle: String {
        title ?? "Unnamed Chat"
    }
}
