import Foundation

enum UserDefaultKey: String {
    case apiKey = "darkbloom_api_key"
    
    enum Migration: String {
        case legacySwiftDataStore = "migration.legacy_data_store"
        case legacyChatsToStableIdentifiers = "migration.chat_stable_ids"
        case fleetToSwiftData = "migration.fleet_to_swift_data"
    }
    
    enum Legacy: String {
        case trackedMachineSerialNumbers = "tracked_machine_serial_numbers"
        case loadTestingApiKeys = "load_testing_api_keys"
        case remoteRestartTargets = "remote_restart_targets"
    }
}

@MainActor @Observable
final class Settings {
    static let shared = Settings()
    
    private let defaults: UserDefaults = UserDefaults.standard
    
    var apiKey: String? {
        didSet { defaults.set(apiKey, forKey: UserDefaultKey.apiKey.rawValue) }
    }
    
    // MARK: Migrations
    
    var migratedLegacySwiftDataStore: Bool {
        didSet {
            defaults.set(
                migratedLegacySwiftDataStore,
                forKey: UserDefaultKey.Migration.legacySwiftDataStore.rawValue
            )
        }
    }
    
    var migratedLegacyChatsToStableIdentifiers: Bool {
        didSet {
            defaults.set(
                migratedLegacyChatsToStableIdentifiers,
                forKey: UserDefaultKey.Migration.legacyChatsToStableIdentifiers.rawValue
            )
        }
    }
    
    var migratedFleetToSwiftData: Bool {
        didSet {
            defaults.set(
                migratedFleetToSwiftData,
                forKey: UserDefaultKey.Migration.fleetToSwiftData.rawValue
            )
        }
    }
    
    // MARK: Legacy
    
    var loadTestingApiKeys: [String] {
        didSet {
            defaults.set(
                loadTestingApiKeys.joined(separator: ","),
                forKey: UserDefaultKey.Legacy.loadTestingApiKeys.rawValue
            )
        }
    }
    
    // MARK: Initializer
    
    private init() {
        self.apiKey = defaults.string(forKey: UserDefaultKey.apiKey.rawValue)
        
        self.migratedLegacySwiftDataStore = defaults.bool(
            forKey: UserDefaultKey.Migration.legacySwiftDataStore.rawValue
        )
        
        self.migratedLegacyChatsToStableIdentifiers = defaults.bool(
            forKey: UserDefaultKey.Migration.legacyChatsToStableIdentifiers.rawValue
        )
        
        self.migratedFleetToSwiftData = defaults.bool(
            forKey: UserDefaultKey.Migration.fleetToSwiftData.rawValue
        )
        
        self.loadTestingApiKeys = defaults
            .string(forKey: UserDefaultKey.Legacy.loadTestingApiKeys.rawValue)
            .map { $0.split(separator: ",").map(String.init) } ?? []
    }
}
