import Foundation

struct DarkbloomProviderStat: Decodable, Equatable {
    let id: String
    let attested: Bool
    let chip: String
    let status: DarkbloomProviderStatus
    let trustLevel: DarkbloomProviderTrustLevel
    let runtimeVerified: Bool
    
    let cpuCores: DarkbloomCPUCoreInfo
    let gpuCores: Int
    
    let memoryGb: Int
    let memoryBandwidthGbs: Double
    
    let requestsServed: Int
    let tokensGenerated: Int
    
    let models: [DarkbloomModel]
    let currentModel: String
    
    let failedChallenges: Int
    let lastChallengeVerified: String
}

extension DarkbloomProviderStat {
    var isTrusted: Bool {
        trustLevel == .hardware && status != .untrusted
    }
}
