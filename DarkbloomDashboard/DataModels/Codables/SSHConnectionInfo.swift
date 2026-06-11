import Foundation
import CryptoKit
import Citadel

nonisolated struct SSHConnectionInfo: CodableData {
    var user: String
    var host: String
    var passwordKeychainId: String?
}

nonisolated extension SSHConnectionInfo {
    
    var sshClientSettings: SSHClientSettings {
        SSHClientSettings(
            host: host,
            authenticationMethod: {
                if let passwordKeychainId,
                   let password = try? SSHPasswordKeychain.loadPassword(id: passwordKeychainId) {
                    SSHAuthenticationMethod.passwordBased(username: user, password: password)
                } else {
                    SSHAuthenticationMethod.ed25519(username: user, privateKey: Curve25519.Signing.PrivateKey())
                }
            },
            hostKeyValidator: .acceptAnything()
        )
    }
}
