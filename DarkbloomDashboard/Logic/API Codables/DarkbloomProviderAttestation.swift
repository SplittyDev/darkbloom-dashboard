import Foundation

struct DarkbloomProviderAttestation: Decodable, Equatable {
    let acmeVerified: Bool
    let authenticatedRootEnabled: Bool
    let chipName: String
    let gpuCores: Int
    let hardwareModel: String
    let mdaSerial: String?
    let mdaVerified: Bool
    let mdmVerified: Bool
    let memoryGb: Int
    let models: [String]?
    let providerId: String
    let secureBootEnabled: Bool
    let secureEnclave: Bool
    let sePublicKey: String
    let serialNumber: String?
    let sipEnabled: Bool
    let status: DarkbloomProviderStatus
    let trustLevel: DarkbloomProviderTrustLevel
}

extension DarkbloomProviderAttestation {
    var isTrusted: Bool {
        trustLevel == .hardware
        && status != .untrusted
        && authenticatedRootEnabled
        && mdaVerified
        && mdmVerified
        && secureBootEnabled
        && secureEnclave
        && sipEnabled
    }
}
