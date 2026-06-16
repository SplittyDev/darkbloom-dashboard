import Foundation
import SwiftData

@Model
final class AccountBalanceModel {
    var id: UUID
    var createdAt: Date
    var accountId: String
    var availableBalanceMicroUSD: Int
    var withdrawableBalanceMicroUSD: Int
    var totalMicroUSD: Int
    
    init(from earnings: DarkbloomAccountEarnings) {
        id = UUID()
        createdAt = Date.now
        accountId = earnings.accountId
        availableBalanceMicroUSD = earnings.availableBalanceMicroUsd
        withdrawableBalanceMicroUSD = earnings.withdrawableBalanceMicroUsd
        totalMicroUSD = earnings.totalMicroUsd
    }
    
    var earnings: DarkbloomAccountEarnings {
        DarkbloomAccountEarnings(
            accountId: accountId,
            availableBalanceMicroUsd: availableBalanceMicroUSD,
            availableBalanceUsd: MicroUSD.format(availableBalanceMicroUSD),
            count: 0,
            earnings: [],
            historyLimit: 0,
            recentCount: 0,
            totalMicroUsd: totalMicroUSD,
            totalUsd: MicroUSD.format(totalMicroUSD),
            withdrawableBalanceMicroUsd: withdrawableBalanceMicroUSD,
            withdrawableBalanceUsd: MicroUSD.format(withdrawableBalanceMicroUSD)
        )
    }
}
