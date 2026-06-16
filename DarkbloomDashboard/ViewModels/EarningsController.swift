import Foundation
import Observation

import Foundation
import Observation

struct ProjectedEarnings: Equatable {
    let projectedEarnings24h: Double?
    let projectedEarningsPerWeek: Double?
    let projectedEarningsPerMonth: Double?
    
    let currentMonthlyPace: Double?
    let hourlyMonthlyPace: Double?
    let dailyMonthlyPace: Double?
    let weightedMonthlyProjection: Double?
    
    let observedEarningsMicroUSD: Int
    let observedEarnings: Double
    let observedDuration: TimeInterval?
    let oldestSnapshotDate: Date?
    let newestSnapshotDate: Date?
}

@MainActor @Observable
final class EarningsController {
    static let shared = EarningsController()
    
    private(set) var projectedEarnings: ProjectedEarnings?
    
    private init() {}
    
    func calculateProjections(basedOn balances: [AccountBalanceModel]) {
        let snapshots: [(date: Date, earnings: DarkbloomAccountEarnings)] = balances.map {
            (date: $0.createdAt, earnings: $0.earnings)
        }
        
        Task {
            await calculateProjections(basedOn: snapshots)
        }
    }
    
    @concurrent func calculateProjections(
        basedOn snapshots: [(date: Date, earnings: DarkbloomAccountEarnings)]
    ) async {
        let sortedSnapshots = snapshots.sorted { $0.date < $1.date }
        
        guard sortedSnapshots.count >= 2 else {
            await MainActor.run {
                self.projectedEarnings = nil
            }
            return
        }
        
        let now = Date()
        
        let allTimeDelta = balanceDelta(in: sortedSnapshots)
        
        let last15mDelta = balanceDelta(
            in: sortedSnapshots,
            since: now.addingTimeInterval(-15 * 60)
        )
        
        let last1hDelta = balanceDelta(
            in: sortedSnapshots,
            since: now.addingTimeInterval(-60 * 60)
        )
        
        let last24hDelta = balanceDelta(
            in: sortedSnapshots,
            since: now.addingTimeInterval(-24 * 60 * 60)
        )
        
        let currentMonthlyPace = monthlyPace(
            from: last15mDelta,
            minimumUsefulSeconds: 5 * 60
        )
        
        let hourlyMonthlyPace = monthlyPace(
            from: last1hDelta,
            minimumUsefulSeconds: 15 * 60
        )
        
        let dailyMonthlyPace = monthlyPace(
            from: last24hDelta,
            minimumUsefulSeconds: 60 * 60
        )
        
        let weightedMonthlyProjection = weightedMonthlyProjection(
            current15m: currentMonthlyPace,
            hourly: hourlyMonthlyPace,
            daily: dailyMonthlyPace
        )
        
        let allTime24h = pace(from: allTimeDelta, over: 60 * 60 * 24)
        let allTimeWeek = pace(from: allTimeDelta, over: 60 * 60 * 24 * 7)
        let allTimeMonth = pace(from: allTimeDelta, over: 60 * 60 * 24 * 30.4375)
        
        let observedEarningsMicroUSD = allTimeDelta?.amountMicroUSD ?? 0
        
        let projection = ProjectedEarnings(
            projectedEarnings24h: allTime24h,
            projectedEarningsPerWeek: allTimeWeek,
            projectedEarningsPerMonth: allTimeMonth,
            currentMonthlyPace: currentMonthlyPace,
            hourlyMonthlyPace: hourlyMonthlyPace,
            dailyMonthlyPace: dailyMonthlyPace,
            weightedMonthlyProjection: weightedMonthlyProjection,
            observedEarningsMicroUSD: observedEarningsMicroUSD,
            observedEarnings: MicroUSD.toUsd(observedEarningsMicroUSD),
            observedDuration: allTimeDelta?.duration,
            oldestSnapshotDate: sortedSnapshots.first?.date,
            newestSnapshotDate: sortedSnapshots.last?.date
        )
        
        await MainActor.run {
            self.projectedEarnings = projection
        }
    }
}

private struct BalanceDelta {
    let amountMicroUSD: Int
    let duration: TimeInterval
    let startDate: Date
    let endDate: Date
}

private nonisolated extension EarningsController {
    
    func balanceDelta(
        in snapshots: [(date: Date, earnings: DarkbloomAccountEarnings)]
    ) -> BalanceDelta? {
        guard let first = snapshots.first,
              let last = snapshots.last else {
            return nil
        }
        
        return balanceDelta(from: first, to: last)
    }
    
    func balanceDelta(
        in snapshots: [(date: Date, earnings: DarkbloomAccountEarnings)],
        since startDate: Date
    ) -> BalanceDelta? {
        guard let endSnapshot = snapshots.last else {
            return nil
        }
        
        let startSnapshot = snapshots.last { $0.date <= startDate } ?? snapshots.first
        
        guard let startSnapshot else {
            return nil
        }
        
        return balanceDelta(from: startSnapshot, to: endSnapshot)
    }
    
    func balanceDelta(
        from start: (date: Date, earnings: DarkbloomAccountEarnings),
        to end: (date: Date, earnings: DarkbloomAccountEarnings)
    ) -> BalanceDelta? {
        let duration = end.date.timeIntervalSince(start.date)
        
        guard duration > 0 else {
            return nil
        }
        
        let deltaMicroUSD = end.earnings.totalMicroUsd - start.earnings.totalMicroUsd
        
        // Balance went down, probably withdrawal/correction.
        // Don't treat it as negative earnings.
        guard deltaMicroUSD >= 0 else {
            return nil
        }
        
        return BalanceDelta(
            amountMicroUSD: deltaMicroUSD,
            duration: duration,
            startDate: start.date,
            endDate: end.date
        )
    }
    
    func pace(from delta: BalanceDelta?, over duration: TimeInterval) -> Double? {
        guard let delta else {
            return nil
        }
        
        guard delta.duration > 0 else {
            return nil
        }
        
        let projectedMicroUSD = Double(delta.amountMicroUSD) / delta.duration * duration
        
        return MicroUSD.toUsd(projectedMicroUSD)
    }
    
    func monthlyPace(
        from delta: BalanceDelta?,
        minimumUsefulSeconds: TimeInterval
    ) -> Double? {
        guard let delta else {
            return nil
        }
        
        guard delta.duration >= minimumUsefulSeconds else {
            return nil
        }
        
        return pace(from: delta, over: 60 * 60 * 24 * 30.4375)
    }
    
    func weightedMonthlyProjection(
        current15m: Double?,
        hourly: Double?,
        daily: Double?
    ) -> Double? {
        var values: [(value: Double, weight: Double)] = []
        
        if let current15m {
            values.append((current15m, 0.15))
        }
        
        if let hourly {
            values.append((hourly, 0.35))
        }
        
        if let daily {
            values.append((daily, 0.50))
        }
        
        guard !values.isEmpty else {
            return nil
        }
        
        let totalWeight = values.reduce(0) { $0 + $1.weight }
        
        return values.reduce(0) { result, item in
            result + item.value * (item.weight / totalWeight)
        }
    }
}
