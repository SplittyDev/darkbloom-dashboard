import Foundation

struct DarkbloomModelAttestation: Decodable {
    let secureBoot: Bool
    let secureEnclave: Bool
    let sipEnabled: Bool
}
