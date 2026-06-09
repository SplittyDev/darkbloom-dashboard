import SwiftUI
import FiveKit

struct OverviewTab: View {
    @Environment(APIDataController.self) private var dataController
    @Environment(EarningsController.self) private var earningsController
    
    #if os(macOS)
    @Environment(LocalServiceController.self) private var localServiceController: LocalServiceController?
    #endif
    
    private let settings = Settings.shared
    
    var body: some View {
        Form {
            APIKeySection()
            
            EarningsSection()
            
            #if os(macOS)
            // TODO: This only shows up if darkbloom exists locally, but the fleet restart button is in this section.
            if let localServiceController, localServiceController.darkbloomExists() {
                LocalDarkbloomSection(localServiceController: localServiceController)
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
