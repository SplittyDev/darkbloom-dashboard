import SwiftUI

struct ControllerPreviewModifier: PreviewModifier {
    private let dataController = APIDataController.shared
    private let earningsController = EarningsController.shared
    
    #if os(macOS)
    private let localServiceController = LocalServiceController.shared
    private let loadTestingController = LoadTestingController.shared
    private let localLogController = LocalLogController.shared
    private let restartController = RestartController.shared
    #endif
    
    static func makeSharedContext() async throws -> () {
    }

    func body(content: Content, context: ()) -> some View {
        content
            .environment(dataController)
            .environment(earningsController)
            #if os(macOS)
            .environment(localServiceController)
            .environment(loadTestingController)
            .environment(localLogController)
            .environment(restartController)
            #endif
    }
}

@available(iOS 18, *)
extension PreviewTrait where T == Preview.ViewTraits {

    /// Injects essential controllers into the environment.
    @MainActor static var controllers: Self = .modifier(ControllerPreviewModifier())
}
