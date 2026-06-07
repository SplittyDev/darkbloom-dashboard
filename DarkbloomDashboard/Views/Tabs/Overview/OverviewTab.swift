import SwiftUI
import FiveKit

struct OverviewTab: View {
    @Environment(APIDataController.self) private var dataController
    @Environment(EarningsViewModel.self) private var earningsController
    
    #if os(macOS)
    @Environment(LocalServiceController.self) private var localServiceController: LocalServiceController?
    #endif
    
    private let settings = Settings.shared
    
    var body: some View {
        Form {
            APIKeySection()
            
            EarningsSection()
            
            #if os(macOS)
            if let localServiceController, localServiceController.darkbloomExists() {
                LocalDarkbloomSection(localServiceController: localServiceController)
            }
            #endif
            
            TrackedMachineListSection()
        }
        .formStyle(.grouped)
    }
}

#Preview {
    #if os(macOS)
    OverviewTab()
        .environment(APIDataController())
        .environment(LocalServiceController())
    #else
    OverviewTab()
        .environment(APIDataController())
    #endif
}
