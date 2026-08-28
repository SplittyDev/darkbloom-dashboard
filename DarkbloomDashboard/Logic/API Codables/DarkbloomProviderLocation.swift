import Foundation

struct DarkbloomProviderLocation: Decodable, Hashable {
    let key: String
    let scope: DarkbloomLocationScope
    let city: String?
    let region: String?
    let regionCode: String?
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
    let providers: Int
    let hardwareAttested: Int
    let gpuCores: Int
    let memoryGb: Int
}

extension DarkbloomProviderLocation {
    var fullDisplayName: String {
        let components: [String?] = [
            city,
            region,
            country,
        ]
        return components.compactMap(\.self).joined(separator: ", ")
    }
    
    var compactDisplayName: String {
        let components: [String?] = [
            city,
            regionCode,
            countryCode,
        ]
        return components.compactMap(\.self).joined(separator: ", ")
    }
}
