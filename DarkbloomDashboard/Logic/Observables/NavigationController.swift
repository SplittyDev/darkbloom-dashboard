import Foundation

@MainActor @Observable
final class NavigationController {
    static let shared = NavigationController()
    
    var activeTab: SidebarTab = .overview
    
    private init() {}
}
