#if os(iOS)

import SwiftUI
import FiveKit

extension ChatDetailTab {
    private enum FocusedField: Hashable {
        case messageComposer
    }
    
    struct ChatMessageComposer_iOS: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        @Binding var text: String
        
        let canSend: Bool
        let sendMessage: () -> Void
        
        @FocusState private var focusedField: FocusedField?
        
        var body: some View {
            HStack {
                MessageComposerTextField(text: $text)
                    .focused($focusedField, equals: .messageComposer)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                
                Button {
                    sendMessage()
                } label: {
                    Text(Image(systemName: "arrow.up"))
                }
                .buttonBorderShape(.circle)
                .apply { btn in
                    if #available(iOS 26, macOS 26, *) {
                        if canSend {
                            btn.buttonStyle(.glassProminent)
                        } else {
                            btn.buttonStyle(.glass)
                        }
                    } else {
                        if canSend {
                            btn.buttonStyle(.borderedProminent)
                        } else {
                            btn.buttonStyle(.bordered)
                        }
                    }
                }
                .disabled(!canSend || viewModel.inProgress)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(.thinMaterial)
            .clipShape(.rect(cornerRadius: 24))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(100))) {
                    focusedField = .messageComposer
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var text: String = ""
    
    ScrollView {
    }
    .safeAreaBarOrInset(edge: .bottom) {
        ChatDetailTab.ChatMessageComposer_iOS(
            text: $text,
            canSend: !text.isEmpty,
            sendMessage: {}
        )
    }
    .environment(ChatViewModel())
}

#endif
