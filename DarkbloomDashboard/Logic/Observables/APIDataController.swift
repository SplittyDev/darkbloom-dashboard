import Foundation
import SwiftData
import FiveKit

@MainActor @Observable
final class APIDataController {
    static let shared = APIDataController()
    
    private var client: DarkbloomClient?
    
    private var statsAndAttestationsTask: Task<Void, any Error>?
    private var balanceTask: Task<Void, any Error>?
    private var modelsTask: Task<Void, any Error>?
    
    private(set) var stats: DarkbloomStats?
    private(set) var attestations: DarkbloomAttestations?
    // private(set) var balance: DarkbloomBalance?
    private(set) var accountEarnings: DarkbloomAccountEarnings? {
        didSet {
            guard let accountEarnings else { return }
            let model = AccountBalanceModel(from: accountEarnings)
            SwiftDataUtils.activeModelContainer.mainContext.insert(model)
        }
    }
    private(set) var models: [DarkbloomModelData]?
    private(set) var machineInfo: [String: MachineInfo] = [:]
    
    private(set) var lastStatUpdate: Date?
    private(set) var lastBalanceUpdate: Date?
    private(set) var lastModelUpdate: Date?
    
    private(set) var isUpdatingStats: Bool = false
    private(set) var isUpdatingBalance: Bool = false
    private(set) var isUpdatingModels: Bool = false
    
    enum CustomError: LocalizedError {
        case combinedError([any Error])
        
        var errorDescription: String {
            switch self {
                case .combinedError(let errors):
                    if errors.count == 1 {
                        return String(describing: errors[0])
                    } else {
                        let descriptions = errors.enumerated().map { offset, error in
                            "Error[\(offset)]: \(String(describing: error))"
                        }
                        return descriptions.joined(separator: "\n")
                    }
            }
        }
    }
    
    private init() {
        if let apiKey = Settings.shared.apiKey {
            Task {
                try? await self.update(apiKey: apiKey)
            }
        }
    }
    
    func clearMachineInfo(for serial: String) {
        machineInfo.removeValue(forKey: serial)
    }
    
    func warmup(serialNumber: String) async throws {
        guard let client else { return }
        try await client.warmupMachine(
            serialNumber: serialNumber,
            models: DarkbloomModel.recommendedCases.map(\.rawValue)
        )
    }
    
    func warmup(model: DarkbloomModel, for serialNumber: String) async throws {
        guard let client else { return }
        try await client.warmupMachine(
            serialNumber: serialNumber,
            models: [model.id]
        )
    }
    
    func update(apiKey: String) async throws {
        self.client = DarkbloomClient(apiKey: apiKey)
        await self.update()
    }
    
    func stopAllUpdates() {
        self.statsAndAttestationsTask?.cancel()
        self.balanceTask?.cancel()
        self.modelsTask?.cancel()
    }
    
    func updateModels() {
        self.modelsTask?.cancel()
        self.modelsTask = Task {
            var isInRetry: Bool = false
            var backoff: TimeInterval = 1
            
            while !Task.isCancelled {
                self.isUpdatingModels = true
                
                do {
                    try await self.refreshModels()
                    isInRetry = false
                    backoff = 1
                } catch {
                    if isInRetry {
                        backoff = min(60, backoff * 2)
                    }
                    isInRetry = true
                    try await Task.sleep(for: .seconds(backoff))
                    continue
                }
                
                self.lastModelUpdate = Date.now
                self.isUpdatingModels = false
                
                let fuzzFactor = Double.random(in: -5..<5)
                try await Task.sleep(for: .seconds(120 + fuzzFactor))
            }
        }
    }
    
    func updateStatsAndAttestations() {
        self.statsAndAttestationsTask?.cancel()
        self.statsAndAttestationsTask = Task {
            var isInRetry: Bool = false
            var backoff: TimeInterval = 1
            
            while !Task.isCancelled {
                self.isUpdatingStats = true
                
                do {
                    try await self.refreshStatsAndAttestations()
                    isInRetry = false
                    backoff = 1
                } catch {
                    if isInRetry {
                        backoff = min(60, backoff * 2)
                    }
                    isInRetry = true
                    try await Task.sleep(for: .seconds(backoff))
                    continue
                }
                
                self.lastStatUpdate = Date.now
                self.isUpdatingStats = false
                
                let fuzzFactor = Double.random(in: -1..<1)
                try await Task.sleep(for: .seconds(60 + fuzzFactor))
            }
        }
    }
    
    func updateBalance() {
        self.balanceTask?.cancel()
        self.balanceTask = Task {
            var isInRetry: Bool = false
            var backoff: TimeInterval = 1
            
            while !Task.isCancelled {
                self.isUpdatingBalance = true
                
                do {
                    try await self.refreshBalance()
                    isInRetry = false
                    backoff = 1
                } catch {
                    if isInRetry {
                        backoff = min(60, backoff * 2)
                    }
                    isInRetry = true
                    try await Task.sleep(for: .seconds(backoff))
                    continue
                }
                
                self.lastBalanceUpdate = Date.now
                self.isUpdatingBalance = false
                
                let fuzzFactor = Double.random(in: -1..<1)
                try await Task.sleep(for: .seconds(60 + fuzzFactor))
            }
        }
    }
    
    func update() async {
        
        // Cancel all tasks
        self.statsAndAttestationsTask?.cancel()
        self.balanceTask?.cancel()
        self.modelsTask?.cancel()
        
        self.updateStatsAndAttestations()
        try? await Task.sleep(for: .seconds(2))
        
        self.updateBalance()
        try? await Task.sleep(for: .seconds(2))
        
        self.updateModels()
    }
    
    func refreshStatsAndAttestations() async throws {
        var didRefreshAny: Bool = false
        var errors: [any Error] = []
        do {
            self.stats = try await client?.stats()
            didRefreshAny = true
        } catch {
            print(error)
            errors.append(error)
        }
        do {
            self.attestations = try await client?.attestations()
            didRefreshAny = true
        } catch {
            print(error)
            errors.append(error)
        }
        if didRefreshAny {
            self.refreshMachineInformation()
        }
        if errors.count == 1, let onlyError = errors.first {
            throw onlyError
        } else if errors.count > 1 {
            throw CustomError.combinedError(errors)
        }
    }
    
    private func refreshModels() async throws {
        do {
            self.models = try await client?.models().data
                .sorted(by: \.metadata.routableProviders, ascending: false, secondary: \.id)
        } catch {
            print(error)
            throw error
        }
    }
    
    private func fetchBalance() async throws -> DarkbloomBalance? {
        do {
            return try await client?.balance()
        } catch {
            print(error)
            throw error
        }
    }
    
    private func fetchAccountEarnings() async throws -> DarkbloomAccountEarnings? {
        do {
            return try await client?.accountEarnings()
        } catch {
            print(error)
            throw error
        }
    }
    
    private func refreshBalance() async throws {
        guard let currentBalance = try await self.fetchAccountEarnings() else { return }
        if let previousBalance = self.accountEarnings {
            let microUsdDiff = max(0, currentBalance.totalMicroUsd - previousBalance.totalMicroUsd)
            
            // Do not update state if diff is 0
            if microUsdDiff == 0 {
                return
            }
        }
        self.accountEarnings = currentBalance
    }
    
    private func refreshMachineInformation() {
        guard let stats, let attestations else { return }
        for provider in attestations.providers {
            guard let providerStats = stats.providers.first(where: { $0.id == provider.providerId }) else {
                continue
            }
            let machineInfo = MachineInfo(
                providerId: provider.providerId,
                serialNumber: provider.serialNumber,
                trust: MachineTrustInfo(
                    status: provider.status,
                    trustLevel: provider.trustLevel,
                    attested: providerStats.attested,
                    acmeVerified: provider.acmeVerified,
                    authenticatedRootEnabled: provider.authenticatedRootEnabled,
                    mdaSerial: provider.mdaSerial,
                    mdaVerified: provider.mdaVerified,
                    mdmVerified: provider.mdmVerified,
                    secureBootEnabled: provider.secureBootEnabled,
                    secureEnclave: provider.secureEnclave,
                    sipEnabled: provider.sipEnabled,
                    runtimeVerified: providerStats.runtimeVerified
                ),
                hardware: MachineHardwareInfo(
                    modelIdentifier: provider.hardwareModel,
                    chipName: provider.chipName,
                    cpuCores: providerStats.cpuCores,
                    gpuCores: providerStats.gpuCores,
                    memoryGb: providerStats.memoryGb,
                    memoryBandwidthGbs: Int(providerStats.memoryBandwidthGbs)
                ),
                activity: MachineActivityInfo(
                    requestsServed: providerStats.requestsServed,
                    tokensGenerated: providerStats.tokensGenerated,
                    lastChallengeVerified: providerStats.lastChallengeVerified,
                    failedChallenges: providerStats.failedChallenges,
                    models: providerStats.models
                )
            )
            if let serialNumber = provider.serialNumber {
                self.machineInfo[serialNumber] = machineInfo
            }
        }
    }
    
    var routableProviderCount: Int? {
        guard let attestations else { return 0 }
        return attestations.providers.count(where: \.isTrusted)
    }
}
