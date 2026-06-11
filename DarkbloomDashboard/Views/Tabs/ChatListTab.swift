import SwiftUI
import SwiftData

private enum NavigationValue: Hashable {
    case chat(ChatModel)
    case newChat
}

struct ChatListTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatModel.updatedAt, order: .reverse) private var chats: [ChatModel]
    
    var body: some View {
        List {
            ForEach(chats) { chat in
                NavigationLink(value: NavigationValue.chat(chat)) {
                    Text(chat.resolvedTitle)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let chat = chats[index]
                    modelContext.delete(chat)
                }
                try? modelContext.save()
            }
            .animation(.default, value: chats)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(value: NavigationValue.newChat) {
                    Label("New Chat", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: NavigationValue.self) { navValue in
            Group {
                switch navValue {
                    case .chat(let chat):
                        ChatDetailTab(chatId: chat.stableId)
                            .navigationTitle(chat.resolvedTitle)
                    case .newChat:
                        ChatDetailTab()
                            .navigationTitle("Unnamed Chat")
                }
            }
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
        }
    }
}

#Preview(traits: .controllers) {
    NavigationStack {
        ChatListTab()
            .navigationTitle("Chats")
    }
}
