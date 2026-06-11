import Foundation
import SwiftData

@Observable
final class FleetController {
    static let shared = FleetController()
    
    private(set) var machines: [MachineModel] = []
    
    var machineSerialNumbers: [String] {
        machines.map(\.serialNo)
    }
    
    private init() {}
    
    func updateMachines(_ machines: [MachineModel]) {
        self.machines = machines
    }
    
    func machine(withSerialNo serialNo: String) -> MachineModel? {
        machines.first(where: { $0.serialNo == serialNo })
    }
}
