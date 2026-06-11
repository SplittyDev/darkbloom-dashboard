import SwiftUI

struct PrivacyToggle: View {
    @Environment(UIPreferenceController.self) private var uiPreferenceController
    
    var body: some View {
        Button {
            withAnimation {
                uiPreferenceController.usesPrivacyMode.toggle()
            }
        } label: {
            let systemImage: String = uiPreferenceController.usesPrivacyMode ? "eye.slash" : "eye"
            Text(Image(systemName: systemImage))
        }
    }
}
