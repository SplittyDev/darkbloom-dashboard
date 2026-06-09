import SwiftUI
import FiveKit
import MarkdownView

extension ChatDetailTab {
    struct AssistantMessageView: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        let message: ChatMessageModel
        let isStreaming: Bool
        
        private var content: String {
            if isStreaming {
                message.content.fixingMarkdown
            } else {
                message.content
            }
        }
        
        var body: some View {
            VStack(alignment: .leading) {
                if message.content.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    MarkdownView(content)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack {
                    if let usage = message.usage {
                        Text("Usage: \(usage.promptTokens) in, \(usage.completionTokens) out")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.leading)
            .containerRelativeFrame(.horizontal, alignment: .leading) { length, _ in
                length * 0.9
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.interactiveSpring, value: message.content)
        }
    }
}
