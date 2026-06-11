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
    
    init(serialNo: String) {
        self.serialNo = serialNo
    }
}

extension MachineModel {
    
    @MainActor
    var currentInfo: MachineInfo? {
        APIDataController.shared.machineInfo[serialNo]
    }
}
