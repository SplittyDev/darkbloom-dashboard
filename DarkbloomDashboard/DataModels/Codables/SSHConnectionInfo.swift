import Foundation

nonisolated struct SSHConnectionInfo: CodableData {
    var user: String
    var host: String
    var passwordKeychainId: String?
}

nonisolated extension SSHConnectionInfo {
    
    /// - Warning: This should not be used going forward, as it doesn't support password auth.
    var sshRestartArguments: [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(user)@\(host)",
            "~/.darkbloom/bin/darkbloom stop; sleep 2; ~/.darkbloom/bin/darkbloom start --all"
        ]
    }
}
