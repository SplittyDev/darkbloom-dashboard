import SwiftUI
import SwiftData
import FiveKit

struct SidebarChatLink: View {
    @Environment(\.modelContext) private var modelContext
    
    let chat: ChatModel
    
    var body: some View {
        NavigationLink(value: SidebarTab.chat(chat.persistentModelID)) {
            HStack {
                if chat.isGeneratingTitle {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.blurReplace)
                }
                Label(chat.resolvedTitle, systemImage: "text.bubble")
                    .contentTransition(.interpolate)
            }
        }
        .contextMenu {
            DeleteButton {
                modelContext.delete(chat)
            }
        }
        .animation(.smooth, value: chat.title)
        .animation(.smooth, value: chat.isGeneratingTitle)
    }
}
