import Foundation
import SwiftData

enum SidebarTab: Hashable, Identifiable {
    case overview
    case network
    case models
    case machine(String)
    case machines
    case chat(UUID?)
    case chats
    case loadGenerator
    case logs

    var id: String {
        switch self {
            case .overview: "overview"
            case .network: "network"
            case .models: "models"
            case .machine(let id): "machine-\(id)"
            case .machines: "machines"
            case .chat(let id): if let id { "chat-\(id)" } else { "new-chat" }
            case .chats: "chats"
            case .loadGenerator: "load-generator"
            case .logs: "logs"
        }
    }

    var title: String {
        switch self {
            case .overview: "Overview"
            case .network: "Network"
            case .models: "Models"
            case .machine(let id): id
            case .machines: "Fleet"
            case .chat: "Chat"
            case .chats: "Chats"
            case .loadGenerator: "Load Generator"
            case .logs: "Log Viewer"
        }
    }

    var systemImage: String {
        switch self {
            case .overview: "gauge.with.dots.needle.67percent"
            case .network: "network"
            case .models: "list.dash"
            case .machine: "macstudio"
            case .machines: "macstudio"
            case .chat: "text.bubble"
            case .chats: "bubble.left.and.bubble.right"
            case .loadGenerator: "bolt.fill"
            case .logs: "text.page"
        }
    }
}
