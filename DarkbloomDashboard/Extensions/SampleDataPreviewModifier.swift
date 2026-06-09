import SwiftUI
import SwiftData
import FiveKit

struct SampleDataPreviewModifier: PreviewModifier {

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

        // Save and return
        try? modelContext.save()
        return modelContainer
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
    }
}

struct ModelContextPreviewModifier: PreviewModifier {

    static func makeSharedContext() async throws -> ModelContainer {
        SwiftDataUtils.activeModelContainer
    }

    func body(content: Content, context: ModelContainer) -> some View {
        content.modelContainer(context)
    }
}

@available(iOS 18, *)
extension PreviewTrait where T == Preview.ViewTraits {

    /// Injects a `ModelContainer` with sample data.
    @MainActor static var sampleData: Self = .modifier(SampleDataPreviewModifier())

    /// Injects a `ModelContainer`.
    @MainActor static var modelContext: Self = .modifier(ModelContextPreviewModifier())
}
