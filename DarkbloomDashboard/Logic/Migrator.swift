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
        migrateLegacySwiftDataStore()
        migrateLegacyChatsToStableIdentifiers()
        migrateFleetToSwiftData()
    }
    
    private func migrateLegacySwiftDataStore() {
        guard !settings.migratedLegacySwiftDataStore else { return }
        
        // This migration always succeeds.
        defer {
            print("Migrated previous SwiftData store to new location.")
            settings.migratedLegacySwiftDataStore = true
        }
        
        // Load legacy model container from default location
        let modelConfiguration = ModelConfiguration(schema: SwiftDataUtils.schema, isStoredInMemoryOnly: false)
        guard let legacyContainer = try? ModelContainer(
            for: SwiftDataUtils.schema,
            configurations: [modelConfiguration]
        ) else {
            return
        }
        
        // Get legacy model context from legacy model container
        let legacyContext = legacyContainer.mainContext
        
        // Initialize migration statistics
        var migratedMachineCount: Int = 0
        var migratedChatCount: Int = 0
        var migratedChatMessageCount: Int = 0
        var migratedAccountBalanceCount: Int = 0
        
        // Migrate machines
        let fdMachines = FetchDescriptor(predicate: Predicate<MachineModel>.true)
        let legacyMachines = (try? legacyContext.fetch(fdMachines)) ?? []
        let currentMachines = (try? modelContext.fetch(fdMachines)) ?? []
        for machine in legacyMachines {
            
            // Skip machines that already exist in the current model container
            guard !currentMachines.contains(where: { $0.serialNo == machine.serialNo }) else {
                print("Skipping migration of legacy machine: \(machine.serialNo)")
                continue
            }
            
            let clone = MachineModel(serialNo: machine.serialNo, autoWarmup: machine.autoWarmup)
            clone.sshConnectionInfo = machine.sshConnectionInfo
            modelContext.insert(machine)
            migratedMachineCount += 1
        }
        try? modelContext.save()
        
        // Migrate chats
        let fdChats = FetchDescriptor(predicate: Predicate<ChatModel>.true)
        let legacyChats = (try? legacyContext.fetch(fdChats)) ?? []
        let currentChats = (try? modelContext.fetch(fdChats)) ?? []
        for chat in legacyChats {
            
            // Skip chats that already exist in the current model container
            guard !currentChats.contains(where: { $0.stableId == chat.stableId }) else {
                print("Skipping migration of legacy chat: \(chat.stableId)")
                continue
            }
            
            let clone = ChatModel(stableId: chat.stableId)
            clone.createdAt = chat.createdAt
            clone.updatedAt = chat.updatedAt
            modelContext.insert(clone)
            migratedChatCount += 1
            
            // Migrate chat messages
            for message in chat.messages {
                let clone = ChatMessageModel(chat: clone, role: message.role, content: message.content)
                clone.createdAt = message.createdAt
                clone.reasoning = message.reasoning
                clone.usage = message.usage
                modelContext.insert(clone)
                migratedChatMessageCount += 1
            }
        }
        try? modelContext.save()
        
        // Migrate balances
        let fdAccountBalances = FetchDescriptor(predicate: Predicate<AccountBalanceModel>.true)
        let legacyBalances = (try? legacyContext.fetch(fdAccountBalances)) ?? []
        for balance in legacyBalances {
            
            // Skip balances that already exist in the current model container
            guard !legacyBalances.contains(where: { $0.id == balance.id }) else {
                print("Skipping migration of legacy account balance: \(balance.id)")
                continue
            }
            
            let darkbloomModel = balance.earnings
            let clone = AccountBalanceModel(from: darkbloomModel)
            clone.id = balance.id
            modelContext.insert(clone)
            migratedAccountBalanceCount += 1
        }
        try? modelContext.save()
        
        print("Migrated \(migratedMachineCount) machines to new data store.")
        print("Migrated \(migratedChatCount) chats with \(migratedChatMessageCount) messages to new data store.")
        print("Migrated \(migratedAccountBalanceCount) account balances to new data store.")
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
