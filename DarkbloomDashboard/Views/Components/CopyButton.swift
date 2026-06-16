import SwiftUI

struct CopyButton: View {
    let value: String
    
    #if os(macOS)
    func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }
    #else
    func copy() {
        UIPasteboard.general.string = value
    }
    #endif
    
    var body: some View {
        Button("Copy", systemImage: "document.on.document") {
            copy()
        }
    }
}

#Preview {
    CopyButton(value: "Hi mom")
}
