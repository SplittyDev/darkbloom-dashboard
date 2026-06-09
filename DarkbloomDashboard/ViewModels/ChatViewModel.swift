import Foundation
import SwiftData
import OpenAI

@MainActor @Observable
final class ChatViewModel {
    let context: ModelContext
    var chat: ChatModel
    
    private(set) var inProgress: Bool = false
    private(set) var streamingMessage: ChatMessageModel?
    
    private var isInserted: Bool
    
    var chatModelIsInserted: Bool {
        isInserted
    }
    
    init() {
        let context = SwiftDataUtils.backgroundContext
        self.context = context
        self.chat = ChatModel()
        self.isInserted = false
    }
    
    init(chatId: PersistentIdentifier) {
        let context = SwiftDataUtils.backgroundContext
        self.context = context
        
        // Refetch model in context
        let fd = FetchDescriptor(predicate: #Predicate<ChatModel> { chat in
            chat.persistentModelID == chatId
        })
        if let results = try? context.fetch(fd), let model = results.first {
            self.chat = model
            self.isInserted = true
        } else {
            fatalError("Chat model with id '\(chatId)' not found in context!")
        }
        
        // Set routing
        
    }
    
    private var client: OpenAI {
        let config = OpenAI.Configuration(
            token: Settings.shared.apiKey,
            host: "api.darkbloom.dev",
            scheme: "https",
            basePath: "/v1",
            parsingOptions: .relaxed
        )
        return OpenAI(configuration: config)
    }
    
    func generateTitle(dataController: APIDataController) async {
        guard chat.title == nil, let text = chat.messages.first?.content else { return }
        
        let systemMessage = """
        Your task is to generate a short title for a chat from the first message.
        Keep the title short and on-point, using no more than three to four words if possible.
        Respond with the plain text title only, and include no other text or formatting.
        """
        
        let chatHistory: [ChatQuery.ChatCompletionMessageParam] = [
            ChatQuery.ChatCompletionMessageParam(role: .system, content: systemMessage)!,
            ChatQuery.ChatCompletionMessageParam(role: .user, content: text)!,
        ]
        
        chat.isGeneratingTitle = true
        try? context.save()
        
        // Find best routing, preferring tracked machines
        let model: DarkbloomModel = .`gpt-oss-20b`
        let idealRouting: ChatRouting = {
            let fleet = Settings.shared.trackedMachineSerialNumbers
            var availableFleet: [String] = []
            for serialNo in fleet {
                guard let machineInfo = dataController.machineInfo[serialNo] else { continue }
                if machineInfo.trust.isTrusted && machineInfo.activity.models.contains(model) {
                    availableFleet.append(serialNo)
                }
            }
            return availableFleet.isEmpty ? .auto : .anyOf(availableFleet)
        }()
        
        let query = ChatQuery(messages: chatHistory, model: model.id, providerSerial: idealRouting.resolved)
        do {
            let response = try await client.chats(query: query)
            if let choice = response.choices.first {
                chat.title = choice.message.content
                chat.isGeneratingTitle = false
                try? context.save()
            }
        } catch {
            print("Error during title generation: \(error)")
            chat.isGeneratingTitle = false
            try? context.save()
        }
    }
    
    func sendMessage(_ text: String) async {
        let wasInserted: Bool = isInserted
        
        // If this is the first response, insert the chat
        if !isInserted {
            context.insert(chat)
            try? context.save()
            self.isInserted = true
        }
        
        // Append own message to chat
        let ownMessageModel = ChatMessageModel(chat: chat, role: .user, content: text)
        chat.messages.append(ownMessageModel)
        try? context.save()
        
        // Build chat history
        var chatHistory: [ChatQuery.ChatCompletionMessageParam] = chat.messages.compactMap { message in
            ChatQuery.ChatCompletionMessageParam(
                role: message.role.openAI,
                content: message.content
            )
        }
        chatHistory.append(ChatQuery.ChatCompletionMessageParam(role: .user, content: text)!)
        
        self.inProgress = true
        defer {
            self.inProgress = false
        }
        
        let streamingMessage = ChatMessageModel(chat: chat, role: .assistant, content: "")
        self.streamingMessage = streamingMessage
        defer {
            self.streamingMessage = nil
        }
        
        do {
            var streamingContent = ""
            self.streamingMessage = streamingMessage
            
            let query = ChatQuery(
                messages: chatHistory,
                model: chat.model.rawValue,
                providerSerial: chat.routing.resolved
            )
            
            for try await chunk in client.chatsStream(query: query) {
                let delta = chunk.choices[0].delta
                if let content = delta.content {
                    streamingContent += content
                    streamingMessage.content = streamingContent
                }
                if let usage = chunk.usage {
                    streamingMessage.usage = ChatMessageTokenUsage(
                        promptTokens: usage.promptTokens,
                        completionTokens: usage.completionTokens,
                        totalTokens: usage.totalTokens
                    )
                }
            }
        } catch {
            print("Error in chat response handling: \(error)")
        }
        
        // Save message as long as it has any content, even if errors were encountered.
        // Darkbloom serves a corrupted final streaming message that always results in a decoding error.
        if !streamingMessage.content.isEmpty {
            chat.messages.append(streamingMessage)
            try? context.save()
        }
        
        // Swap to chat tab if chat was just inserted
        if !wasInserted && isInserted {
            NavigationController.shared.activeTab = .chat(chat.persistentModelID)
        }
    }
    
    func savePendingChanges() {
        guard isInserted else { return }
        try? context.save()
    }
}
