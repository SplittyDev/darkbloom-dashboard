import Foundation

struct DarkbloomModelMetadata: Decodable {
    let attestation: DarkbloomModelAttestation?
    let attestedProviders: Int
    let canAccept: Bool
    let displayName: String
    let modelType: String
    let providerCount: Int
    let quantization: String
    let routableProviders: Int
    let trustLevel: DarkbloomProviderTrustLevel
    let warmProviders: Int
}
