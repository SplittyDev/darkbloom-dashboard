import Foundation
import SwiftData

@MainActor
final class Migrator {
    private let settings = Settings.shared
    
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func run() {
        migrateLegacyChatsToStableIdentifiers()
        migrateFleetToSwiftData()
    }
    
    private func migrateLegacyChatsToStableIdentifiers() {
        guard !settings.migratedLegacyChatsToStableIdentifiers else { return }
        defer {
            print("Migrated legacy chats to stable identifiers.")
            settings.migratedLegacyChatsToStableIdentifiers = true
        }
        
        let fdChats = FetchDescriptor(predicate: Predicate<ChatModel>.true)
        let fdChatResults = try? modelContext.fetch(fdChats)
        var stableIdSet: Set<String> = []
        for chatModel in fdChatResults ?? [] {
            var createNew: Bool = false
            if let stableId = chatModel._stableId {
                if stableIdSet.contains(stableId) {
                    createNew = true
                } else {
                    stableIdSet.insert(stableId)
                }
            } else {
                createNew = true
            }
            if createNew {
                let newStableId = UUID().uuidString
                chatModel._stableId = newStableId
                stableIdSet.insert(newStableId)
            }
        }
        try? modelContext.save()
    }
    
    private func migrateFleetToSwiftData() {
        guard !settings.migratedFleetToSwiftData else { return }
        defer {
            print("Migrated tracked fleet to SwiftData.")
            settings.migratedFleetToSwiftData = true
        }
        
        struct LegacyMachineRestartTarget: Decodable {
            let serialNumber: String
            var user: String
            var host: String
        }
        
        let trackedFleetIds: [String] = UserDefaults.standard
            .string(forKey: UserDefaultKey.Legacy.trackedMachineSerialNumbers.rawValue)
            .map { $0.split(separator: ",").map(String.init) } ?? []
        
        let remoteRestartTargets: [String: LegacyMachineRestartTarget] = UserDefaults.standard
            .data(forKey: UserDefaultKey.Legacy.remoteRestartTargets.rawValue)
            .flatMap { data in
                try? JSONDecoder().decode([String: LegacyMachineRestartTarget].self, from: data)
            } ?? [:]
        
        for serialNo in trackedFleetIds {
            let machineModel = MachineModel(serialNo: serialNo)
            if let restartTarget = remoteRestartTargets[serialNo] {
                machineModel.sshConnectionInfo = SSHConnectionInfo(
                    user: restartTarget.user,
                    host: restartTarget.host
                )
            }
            modelContext.insert(machineModel)
        }
        
        try? modelContext.save()
        
        UserDefaults.standard.removeObject(forKey: UserDefaultKey.Legacy.trackedMachineSerialNumbers.rawValue)
        UserDefaults.standard.removeObject(forKey: UserDefaultKey.Legacy.remoteRestartTargets.rawValue)
    }
}
