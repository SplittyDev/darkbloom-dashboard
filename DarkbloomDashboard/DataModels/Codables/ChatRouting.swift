import Foundation

enum ChatRouting: CodableData, Hashable {
    case auto
    case anyFleet
    case preferFleet
    case anyOf([String])
    case only(String)
}

@MainActor
extension ChatRouting {
    
    var resolved: [String]? {
        switch self {
            case .auto: nil
            case .anyFleet: FleetController.shared.machineSerialNumbers
            case .preferFleet: FleetController.shared.machineSerialNumbers
            case .anyOf(let serials): serials
            case .only(let serial): [serial]
        }
    }
    
    var resolvedWithHeaders: [String]? {
        switch self {
            case .auto: nil
            case .anyFleet: nil // uses "self" routing via headers
            case .preferFleet: nil // uses "prefer" routing via headers
            case .anyOf(let serials): serials
            case .only(let serial): [serial]
        }
    }
    
    var headers: [String: String] {
        switch self {
            case .auto:
                return [:]
            case .anyFleet:
                return ["X-Darkbloom-Routing": "self"]
            case .preferFleet:
                return ["X-Darkbloom-Routing": "prefer"]
            case .anyOf(let array):
                let allSerials = FleetController.shared.machineSerialNumbers
                let allSerialsMatch = array.allSatisfy { serial in
                    allSerials.contains(serial)
                }
                return if allSerialsMatch {
                    ["X-Darkbloom-Routing": "self"]
                } else {
                    [:]
                }
            case .only(let string):
                return if FleetController.shared.machineSerialNumbers.contains(string) {
                    ["X-Darkbloom-Routing": "self"]
                } else {
                    [:]
                }
        }
    }
}
