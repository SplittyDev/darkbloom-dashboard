import SwiftUI
import SwiftData
import FiveKit

struct ChatDetailTab: View {
    @State private var viewModel: ChatViewModel
    
    init() {
        viewModel = ChatViewModel.get()
    }
    
    init(chatId: UUID) {
        viewModel = ChatViewModel.get(chatId: chatId)
    }
    
    var body: some View {
        ScrollView {
            ChatMessagesList()
        }
        .defaultScrollAnchor(.bottom, for: .alignment)
        .scrollDismissesKeyboard(.interactively)
        .apply { view in
            if #available(iOS 26, macOS 26, *) {
                view
                    .scrollEdgeEffectStyle(.soft, for: .vertical)
            } else {
                view
            }
        }
        .safeAreaBarOrInset(edge: .bottom) {
            ChatMessageComposer()
                .frame(maxWidth: 650, alignment: .center)
                .padding(.top, 8)
                .zIndex(1)
        }
        .environment(viewModel)
        .onAppear {
            guard viewModel.chatModelIsInserted else { return }
            viewModel.generateTitle()
        }
        .onDisappear {
            viewModel.savePendingChanges()
        }
    }
}

#Preview(traits: .controllers) {
    let chat: ChatModel = {
        let container = SwiftDataUtils.activeModelContainer
        let context = ModelContext(container)
        let chat = ChatModel()
        let messages: [ChatMessageModel] = [
            ChatMessageModel(chat: chat, role: .system, content: "You are a helpful assistant"),
            ChatMessageModel(chat: chat, role: .user, content: "Hello"),
            ChatMessageModel(chat: chat, role: .assistant, content: "Hi! What can I do for you?"),
        ]
        context.insert(chat)
        chat.messages.append(contentsOf: messages)
        try? context.save()
        return chat
    }()
    
    ChatDetailTab(chatId: chat.stableId)
        .scenePadding()
}
