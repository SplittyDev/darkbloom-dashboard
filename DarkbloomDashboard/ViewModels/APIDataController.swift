import Foundation

struct BalanceChange: Equatable {
    let diff: Double
    let date: Date
}

@MainActor @Observable
final class APIDataController {
    private var client: DarkbloomClient?
    
    private var statsAndAttestationsTask: Task<Void, any Error>?
    private var balanceTask: Task<Void, any Error>?
    
    private(set) var stats: DarkbloomStats?
    private(set) var attestations: DarkbloomAttestations?
    private(set) var balance: DarkbloomBalance?
    
    private(set) var balanceChanges: [BalanceChange] = []
    private(set) var machineInfo: [String: MachineInfo] = [:]
    
    private(set) var lastStatUpdate: Date?
    private(set) var lastBalanceUpdate: Date?
    
    private(set) var isUpdatingStats: Bool = false
    private(set) var isUpdatingBalance: Bool = false
    
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
    
    init() {
        if let apiKey = Settings.shared.apiKey {
            Task {
                try? await self.update(apiKey: apiKey)
            }
        }
    }
    
    func warmup(serialNumber: String) async throws {
        guard let client else { return }
        try await client.warmupMachine(
            serialNumber: serialNumber,
            models: ["gpt-oss-20b", "gemma-4-26b"]
        )
    }
    
    func update(apiKey: String) async throws {
        self.client = DarkbloomClient(apiKey: apiKey)
        self.update()
    }
    
    func updateStatsAndAttestations() {
        self.statsAndAttestationsTask?.cancel()
        self.statsAndAttestationsTask = Task {
            while !Task.isCancelled {
                self.isUpdatingStats = true
                try? await self.refreshStatsAndAttestations()
                self.lastStatUpdate = Date.now
                self.isUpdatingStats = false
                try await Task.sleep(for: .seconds(60))
            }
        }
    }
    
    func updateBalance() {
        self.balanceTask?.cancel()
        self.balanceTask = Task {
            while !Task.isCancelled {
                self.isUpdatingBalance = true
                try? await self.refreshBalance()
                self.lastBalanceUpdate = Date.now
                self.isUpdatingBalance = false
                try await Task.sleep(for: .seconds(60))
            }
        }
    }
    
    func update() {
        self.updateStatsAndAttestations()
        self.updateBalance()
    }
    
    private func refreshStatsAndAttestations() async throws {
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
    
    private func fetchBalance() async throws -> DarkbloomBalance? {
        do {
            return try await client?.balance()
        } catch {
            print(error)
            throw error
        }
    }
    
    private func refreshBalance() async throws {
        let date = Date.now
        guard let currentBalance = try await self.fetchBalance() else { return }
        if let previousBalance = self.balance {
            let microUsdDiff = max(0, currentBalance.balanceMicroUsd - previousBalance.balanceMicroUsd)
            let diff = Double(microUsdDiff) / 1_000_000.0
            if diff > 0 {
                let change = BalanceChange(diff: diff, date: date)
                balanceChanges.append(change)
            }
        }
        self.balance = currentBalance
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
                    memoryBandwidthGbs: providerStats.memoryBandwidthGbs
                ),
                activity: MachineActivityInfo(
                    requestsServed: providerStats.requestsServed,
                    tokensGenerated: providerStats.tokensGenerated,
                    lastChallengeVerified: providerStats.lastChallengeVerified,
                    failedChallenges: providerStats.failedChallenges,
                    models: providerStats.models
                )
            )
            self.machineInfo[provider.serialNumber] = machineInfo
        }
    }
    
    var routableProviderCount: Int? {
        guard let attestations else { return 0 }
        return attestations.providers.count(where: \.isTrusted)
    }
}
