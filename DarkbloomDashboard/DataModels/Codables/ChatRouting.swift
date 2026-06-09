import Foundation

nonisolated enum ChatRouting: Codable, Hashable {
    case auto
    case anyFleet
    case anyOf([String])
    case only(String)
}

extension ChatRouting {
    
    @MainActor
    var resolved: [String]? {
        switch self {
            case .auto: nil
            case .anyFleet: Settings.shared.trackedMachineSerialNumbers
            case .anyOf(let serials): serials
            case .only(let serial): [serial]
        }
    }
}

nonisolated extension ChatRouting {
    var data: Data? {
        try? JSONEncoder().encode(self)
    }
    
    init?(from data: Data) {
        if let _self = try? JSONDecoder().decode(Self.self, from: data) {
            self = _self
        } else {
            return nil
        }
    }
}
