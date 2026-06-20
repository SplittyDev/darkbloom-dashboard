import Foundation
import SwiftData

@Model
final class MachineModel {
    var serialNo: String
    
    private var _sshConnectionInfo: Data?
    var sshConnectionInfo: SSHConnectionInfo? {
        get { _sshConnectionInfo.flatMap(SSHConnectionInfo.init(from:)) }
        set { _sshConnectionInfo = newValue?.data }
    }
    
    var autoWarmup: Bool = false
    
    init(serialNo: String, autoWarmup: Bool = false) {
        self.serialNo = serialNo
        self.autoWarmup = autoWarmup
    }
}

extension MachineModel {
    
    @MainActor
    var currentInfo: MachineInfo? {
        APIDataController.shared.machineInfo[serialNo]
    }
}
