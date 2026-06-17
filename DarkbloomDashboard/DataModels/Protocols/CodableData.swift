import Foundation

protocol CodableData: Codable {
}

extension CodableData {
    var data: Data? {
        try? JSONEncoder().encode(self)
    }
    
    init?(from data: Data) {
        if let _self = try? JSONDecoder().decode(Self.self, from: data) {
            self = _self
        } else {
            return nil
        }
    }
}
