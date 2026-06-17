import Foundation

@MainActor @Observable
final class UIPreferenceController {
    static let shared = UIPreferenceController()
    
    var usesPrivacyMode: Bool = false
    
    private init() {}
}
