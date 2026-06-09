import SwiftUI
import FiveKit

extension ChatDetailTab {
    struct MessageComposerTextField: View {
        @Binding var text: String
        @State private var selection: TextSelection?
        
        func handleKeyPress(key: KeyPress) -> KeyPress.Result {
            #if os(macOS)
            // Make sure the key combination is shift + return
            guard key.modifiers.contains(.shift) && key.key == .return else {
                return .ignored
            }
            #else
            // On iOS, make sure the key is return
            guard key.key == .return else {
                return .ignored
            }
            #endif

            // Handle missing selection
            guard let selection else {
                text += "\n"
                DispatchQueue.main.async {
                    let newIndex = text.endIndex
                    selection = TextSelection(insertionPoint: newIndex)
                }
                return .handled
            }

            // Handle newline at insertion point
            if selection.isInsertion {
                switch selection.indices {
                    case .selection(let range):
                        let isAtEnd = range.lowerBound == text.endIndex
                        text.insert("\n", at: range.lowerBound)
                        DispatchQueue.main.async {
                            if isAtEnd {
                                self.selection = TextSelection(insertionPoint: text.endIndex)
                            } else {
                                let newIndex = text.index(after: range.lowerBound)
                                self.selection = TextSelection(insertionPoint: newIndex)
                            }
                        }
                        return .handled
                    default:
                        // unsupported
                        return .ignored
                }
            }

            // Handle newline replacing selection
            else {
                switch selection.indices {
                    case .selection(let range):
                        text.removeSubrange(range)
                        text.insert("\n", at: range.lowerBound)
                        DispatchQueue.main.async {
                            let newIndex = text.index(after: range.lowerBound)
                            self.selection = TextSelection(insertionPoint: newIndex)
                        }
                        return .handled
                    default:
                        // unsupported
                        return .ignored
                }
            }
        }
        
        var body: some View {
            TextField("Chat on Darkbloom", text: $text, selection: $selection, axis: .vertical)
                .onKeyPress { key in
                    handleKeyPress(key: key)
                }
        }
    }
}
