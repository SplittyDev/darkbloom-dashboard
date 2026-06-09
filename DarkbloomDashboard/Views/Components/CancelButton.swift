import SwiftUI

struct CancelButton: View {
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            Button(role: .cancel) {
                action()
            }
        } else {
            Button("Cancel", role: .cancel) {
                action()
            }
        }
    }
}

#Preview {
    CancelButton(action: {})
}
