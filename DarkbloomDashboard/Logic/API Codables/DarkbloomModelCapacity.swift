import Foundation

struct DarkbloomModelCapacityResponse: Decodable {
    let models: [DarkbloomModelCapacity]
}

struct DarkbloomModelCapacity: Decodable, Identifiable {
    let id: String
    let canAccept: Bool
    let routableProviders: Int
    let warmProviders: Int
    let activeRequests: Int
    let queuedRequests: Int
    let queueLimit: Int
    let aggregateTps: Double

    var demand: Int {
        activeRequests + queuedRequests
    }

    var demandPerRoutableProvider: Double {
        Double(demand) / Double(max(1, routableProviders))
    }
}
