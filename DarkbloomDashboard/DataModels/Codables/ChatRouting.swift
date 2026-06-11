import Foundation

nonisolated enum ChatRouting: CodableData, Hashable {
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
            case .anyFleet: FleetController.shared.machineSerialNumbers
            case .anyOf(let serials): serials
            case .only(let serial): [serial]
        }
    }
}
