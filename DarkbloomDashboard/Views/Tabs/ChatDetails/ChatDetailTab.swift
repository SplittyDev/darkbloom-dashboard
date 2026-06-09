import SwiftUI
import SwiftData
import FiveKit

struct ChatDetailTab: View {
    @Environment(APIDataController.self) private var dataController
    
    @State private var viewModel: ChatViewModel
    
    init() {
        self._viewModel = State(wrappedValue: ChatViewModel())
    }
    
    init(chatId: PersistentIdentifier) {
        self._viewModel = State(wrappedValue: ChatViewModel(chatId: chatId))
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
        .task {
            guard viewModel.chatModelIsInserted else { return }
            await viewModel.generateTitle(dataController: dataController)
        }
        .onDisappear {
            viewModel.savePendingChanges()
        }
    }
}

#Preview {
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
    
    ChatDetailTab(chatId: chat.persistentModelID)
        .environment(APIDataController())
        .modelContainer(SwiftDataUtils.activeModelContainer)
        .scenePadding()
}
