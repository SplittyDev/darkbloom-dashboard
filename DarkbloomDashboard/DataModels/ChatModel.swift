import Foundation
import SwiftData

@Model
final class ChatModel {
    var createdAt: Date
    var updatedAt: Date
    
    var title: String? = nil
    var isGeneratingTitle: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \ChatMessageModel.chat)
    var messages: [ChatMessageModel] = []
    
    private var _modelId: String?
    var model: DarkbloomModel {
        get {
            if let _modelId {
                DarkbloomModel(rawValue: _modelId)
            } else {
                DarkbloomModel.`gpt-oss-20b`
            }
        }
        set {
            _modelId = newValue.rawValue
        }
    }
    
    private var _routing: Data?
    var routing: ChatRouting {
        get { _routing.flatMap(ChatRouting.init(from:)) ?? .auto }
        set { _routing = newValue.data }
    }
    
    init() {
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
    }
}

extension ChatModel {
    var resolvedTitle: String {
        title ?? "Unnamed Chat"
    }
}
