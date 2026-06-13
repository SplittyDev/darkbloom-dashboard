import Foundation

enum MicroUSD {
    static func fromUsd(_ value: Double) -> Int {
        Int(value * 1_000_000.0)
    }
    
    static func toUsd(_ value: Int) -> Double {
        Double(value) / 1_000_000.0
    }
    
    static func format(_ value: Int) -> String {
        toUsd(value).formatted(.currency(code: "USD"))
    }
}
