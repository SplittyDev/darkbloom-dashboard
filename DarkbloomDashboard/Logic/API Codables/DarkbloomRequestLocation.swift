import Foundation

struct DarkbloomRequestLocation: Decodable, Hashable {
    let key: String
    let scope: DarkbloomLocationScope
    let city: String?
    let region: String?
    let regionCode: String?
    let country: String
    let countryCode: String?
    let latitude: Double
    let longitude: Double
    let requests: Int
    let promptTokens: Int
    let completionTokens: Int
    let providers: Int
}
