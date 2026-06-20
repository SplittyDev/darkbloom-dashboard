import Foundation

private struct WarmupState {
    let serialNo: String
    let task: Task<Void, Never>
}

private class LocalWarmupState {
    let model: DarkbloomModel
    var lastWarmup: Date?
    var dueDate: Date?
    var retryCount: Int = 0
    
    var isDue: Bool {
        guard let dueDate else { return true }
        return Date.now >= dueDate
    }
    
    init(model: DarkbloomModel, lastWarmup: Date?) {
        self.model = model
        self.lastWarmup = lastWarmup
    }
    
    func reset() {
        lastWarmup = Date.now
        dueDate = Date.now.addingTimeInterval(60 * 20)
        retryCount = 0
    }
    
    func retry() {
        retryCount += 1
        let retrySeconds: TimeInterval = min(30.0 * Double(retryCount), 300.0)
        dueDate = Date.now.addingTimeInterval(retrySeconds)
    }
}

@MainActor @Observable
final class WarmupCoordinator {
    static let shared = WarmupCoordinator()
    
    private var isInitialRun: Bool = true
    private var states: [String: WarmupState] = [:]
    private let models: [DarkbloomModel] = DarkbloomModel.recommendedCases
    
    private init() {}
    
    func update(machines: [MachineModel]) {
        Task {
            await self.refreshTasks(for: machines.filter(\.autoWarmup).map(\.serialNo))
        }
    }
    
    private func refreshTasks(for serials: [String]) async {
        
        // Delay first warmup by a few seconds to keep below rate limits
        if isInitialRun {
            isInitialRun = false
            try? await Task.sleep(for: .seconds(30))
        }
        
        // Create tasks for new serials
        for serial in serials where states[serial] == nil {
            states[serial] = WarmupState(
                serialNo: serial,
                task: Task {
                    let localState: [DarkbloomModel: LocalWarmupState] = Dictionary(
                        uniqueKeysWithValues: models.map { ($0, LocalWarmupState(model: $0, lastWarmup: nil)) }
                    )
                    while !Task.isCancelled {
                        for model in models {
                            guard let state = localState[model], state.isDue else { continue }
                            do {
                                try await APIDataController.shared.warmup(model: model, for: serial)
                                print("Automatic warmup of \(model.displayName) for \(serial) succeeded")
                                state.reset()
                            } catch {
                                state.retry()
                                let dueSeconds = (state.dueDate ?? Date.now).timeIntervalSinceNow
                                print("Automatic warmup of \(model.displayName) for \(serial) failed, trying again in \(dueSeconds)s")
                            }
                            // Keep a few seconds between model warmups to stay below rate limits
                            try? await Task.sleep(for: .seconds(5))
                        }
                        let earliestDueDate = localState.values.compactMap(\.dueDate).min() ?? Date.now.addingTimeInterval(60 * 20)
                        print("Scheduled next auto-warmup run for \(earliestDueDate)")
                        try? await Task.sleep(for: .seconds(earliestDueDate.timeIntervalSinceNow))
                    }
                }
            )
            print("Machine \(serial) has been registered for automatic warmup.")
        }
        
        // Cancel tasks for deleted serials
        for serial in states.keys where !serials.contains(serial) {
            states[serial]?.task.cancel()
            states.removeValue(forKey: serial)
            print("Machine \(serial) has been removed from automatic warmup.")
        }
    }
}
