import Foundation

enum DarkbloomProviderStatus: String, Decodable, Equatable {
    case online = "online"
    case offline = "offline"
    case serving = "serving"
    case untrusted = "untrusted"
}

extension DarkbloomProviderStatus {
    var displayName: String {
        switch self {
            case .online: "Online"
            case .offline: "Offline"
            case .serving: "Serving"
            case .untrusted: "Untrusted"
        }
    }
}
