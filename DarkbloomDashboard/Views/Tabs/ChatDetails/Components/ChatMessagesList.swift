import SwiftUI
import FiveKit

extension ChatDetailTab {
    struct ChatMessagesList: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        func shouldShow(_ message: ChatMessageModel) -> Bool {
            switch message.role {
                case .assistant, .user: true
                default: false
            }
        }
        
        var messages: [ChatMessageModel] {
            viewModel.chat.messages
                .filter(shouldShow(_:))
                .sorted(by: \.createdAt, ascending: true)
        }
        
        var body: some View {
            let messages = self.messages
            LazyVStack(spacing: 24) {
                ForEach(messages) { message in
                    switch message.role {
                        case .user: UserMessageView(message: message)
                        default: AssistantMessageView(message: message, isStreaming: false)
                    }
                }
                
                if let streamingMessage = viewModel.streamingMessage {
                    AssistantMessageView(message: streamingMessage, isStreaming: true)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: 650, alignment: .center)
            .animation(.interactiveSpring, value: messages)
        }
    }
}
