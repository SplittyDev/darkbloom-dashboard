import SwiftUI

extension ChatDetailTab {
    struct ChatMessageComposer: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        @State private var text: String = ""
        
        private var canSend: Bool {
            !text.isEmpty
        }
        
        private func sendMessage() {
            let originalText = self.text
            defer { self.text = "" }
            Task {
                await viewModel.sendMessage(originalText)
            }
        }
        
        var body: some View {
            #if os(macOS)
            ChatMessageComposer_macOS(text: $text, canSend: canSend, sendMessage: sendMessage)
            #else
            ChatMessageComposer_iOS(text: $text, canSend: canSend, sendMessage: sendMessage)
            #endif
        }
    }
}
