import Foundation

struct DarkbloomRequestFlowLocation: Decodable {
    let key: String
    let kind: DarkbloomRequestFlowLocationKind
    let city: String
    let region: String
    let regionCode: String?
    let country: String
    let countryCode: String
    let latitude: Double
    let longitude: Double
}
