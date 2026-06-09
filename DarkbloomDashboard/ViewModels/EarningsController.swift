import Foundation

struct ProjectedEarnings: Equatable {
    let projectedEarnings24h: Double
    let projectedEarningsPerWeek: Double
    let projectedEarningsPerMonth: Double
}

@MainActor @Observable
final class EarningsController {
    static let shared = EarningsController()
    
    private(set) var projectedEarnings: ProjectedEarnings?
    
    private init() {}
    
    @concurrent func calculateProjections(basedOn changes: [BalanceChange]) async {
        let sortedChanges = changes.sorted { $0.date < $1.date }
        
        guard sortedChanges.count >= 2 else {
            await MainActor.run {
                self.projectedEarnings = nil
            }
            return
        }
        
        let totalDiff = sortedChanges.reduce(0) { result, change in
            result + change.diff
        }
        
        let firstDate = sortedChanges[0].date
        let lastDate = sortedChanges[sortedChanges.count - 1].date
        
        let observedSeconds = lastDate.timeIntervalSince(firstDate)
        
        guard observedSeconds > 0 else {
            await MainActor.run {
                self.projectedEarnings = nil
            }
            return
        }
        
        let earningsPerSecond = totalDiff / observedSeconds
        
        let day: TimeInterval = 60 * 60 * 24
        let week: TimeInterval = day * 7
        let month: TimeInterval = day * 30
        
        await MainActor.run {
            self.projectedEarnings = ProjectedEarnings(
                projectedEarnings24h: earningsPerSecond * day,
                projectedEarningsPerWeek: earningsPerSecond * week,
                projectedEarningsPerMonth: earningsPerSecond * month
            )
        }
    }
}
