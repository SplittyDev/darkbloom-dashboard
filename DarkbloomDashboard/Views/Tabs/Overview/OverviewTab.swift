import SwiftUI
import FiveKit

struct OverviewTab: View {
    @Environment(APIDataController.self) private var dataController
    @Environment(EarningsController.self) private var earningsController
    
    private let settings = Settings.shared
    
    var body: some View {
        Form {
            APIKeySection()
            
            EarningsSection()
            
            #if os(macOS)
            if LocalServiceController.shared.darkbloomExists() {
                LocalDarkbloomSection()
            }
            #endif
            
            TrackedMachineListSection()
        }
        .formStyle(.grouped)
    }
}

#Preview(traits: .controllers) {
    OverviewTab()
}
