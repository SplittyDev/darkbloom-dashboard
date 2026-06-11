import SwiftUI

struct ConfirmButton: View {
    let action: () -> Void
    
    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            Button(role: .confirm) {
                action()
            }
        } else {
            Button("Done") {
                action()
            }
        }
    }
}

#Preview {
    ConfirmButton(action: {})
}
