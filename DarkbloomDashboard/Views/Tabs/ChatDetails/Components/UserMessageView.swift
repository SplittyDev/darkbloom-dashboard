import SwiftUI
import FiveKit

extension ChatDetailTab {
    struct UserMessageView: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        let message: ChatMessageModel
        
        var body: some View {
            VStack(alignment: .trailing) {
                if message.content.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    Text(message.content)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.systemFill)
            .clipShape(.rect(cornerRadius: 12))
            .containerRelativeFrame(.horizontal, alignment: .trailing) { length, _ in
                length * 0.9
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(.smooth, value: message.content)
        }
    }
}
