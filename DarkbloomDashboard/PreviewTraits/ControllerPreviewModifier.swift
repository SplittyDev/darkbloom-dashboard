import SwiftUI
import SwiftData

struct ControllerPreviewModifier: PreviewModifier {
    private let dataController = APIDataController.shared
    private let fleetController = FleetController.shared
    private let earningsController = EarningsController.shared
    
    #if os(macOS)
    private let localServiceController = LocalServiceController.shared
    private let loadTestingController = LoadTestingController.shared
    private let localLogController = LocalLogController.shared
    private let restartController = RestartController.shared
    #endif
    
    static func makeSharedContext() async throws -> ModelContainer {
        let modelContainer = SwiftDataUtils.activeModelContainer
        let modelContext = ModelContext(modelContainer)
        
        // Insert sample chats
        let chat1 = ChatModel()
        chat1.title = "Hello World"
        chat1.messages = [
            ChatMessageModel(chat: chat1, role: .user, content: "Hello world"),
            ChatMessageModel(chat: chat1, role: .assistant, content: "Hello! What can I do for you?"),
        ]
        modelContext.insert(chat1)
        
        let chat2 = ChatModel()
        chat2.title = "Ahoy Matey"
        chat2.messages = [
            ChatMessageModel(chat: chat2, role: .user, content: "Ahoy Matey"),
            ChatMessageModel(chat: chat2, role: .assistant, content: "Ahoy, yer scurvy dog!"),
        ]
        modelContext.insert(chat2)
        
        let machine1 = MachineModel(serialNo: "NJD6MGW279")
        modelContext.insert(machine1)

        try? modelContext.save()
        
        FleetController.shared.updateMachines([machine1])
        
        return modelContainer
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content
            .environment(dataController)
            .environment(fleetController)
            .environment(earningsController)
            #if os(macOS)
            .environment(localServiceController)
            .environment(loadTestingController)
            .environment(localLogController)
            .environment(restartController)
            #endif
            .modelContainer(context)
    }
}

@available(iOS 18, *)
extension PreviewTrait where T == Preview.ViewTraits {

    /// Injects essential controllers into the environment.
    @MainActor static var controllers: Self = .modifier(ControllerPreviewModifier())
}
