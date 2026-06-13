import Foundation

struct DarkbloomAccountEarnings: Decodable, Equatable {
    let accountId: String
    let availableBalanceMicroUsd: Int
    let availableBalanceUsd: String
    let count: Int
    let earnings: [DarkbloomAccountEarningEntry]
    let historyLimit: Int
    let recentCount: Int
    let totalMicroUsd: Int
    let totalUsd: String
    let withdrawableBalanceMicroUsd: Int
    let withdrawableBalanceUsd: String
}

struct DarkbloomAccountEarningEntry: Decodable, Identifiable, Equatable {
    let accountId: String
    let amountMicroUsd: Int
    let completionTokens: Int
    let createdAt: Date
    let id: Int
    let jobId: String
    let model: DarkbloomModel
    let promptTokens: Int
    let providerId: String
    let providerKey: String
}

extension DarkbloomAccountEarnings: Identifiable {
    var id: String { accountId }
}
