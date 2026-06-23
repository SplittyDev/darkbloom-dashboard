import SwiftUI
import FiveKit

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
        
        private var contentText: Text {
            let content = self.content
            return if let attrStr = try? AttributedString(markdown: content) {
                Text(attrStr)
            } else {
                Text(content)
            }
        }
        
        var body: some View {
            VStack(alignment: .leading) {
                Group {
                    if message.content.isEmpty {
                        Group {
                            if message.reasoning == nil || message.reasoning?.isEmpty == true {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Connecting...")
                                }
                            } else {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text("Thinking...")
                                }
                            }
                        }
                        .transition(.blurReplace)
                    } else {
                        contentText
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .transition(.opacity)
                
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
            .animation(.interactiveSpring, value: message.reasoning)
            .animation(.interactiveSpring, value: message.content)
        }
    }
}
