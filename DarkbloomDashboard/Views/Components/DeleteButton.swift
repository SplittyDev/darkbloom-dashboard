import SwiftUI

struct DeleteButton: View {
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            Button(role: .destructive) {
                action()
            }
        } else {
            Button("Delete", systemImage: "trash", role: .destructive) {
                action()
            }
        }
    }
}

#Preview {
    DeleteButton(action: {})
}
