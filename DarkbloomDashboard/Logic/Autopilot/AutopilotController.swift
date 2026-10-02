#if os(macOS)
import Foundation

struct AutopilotEvent: Codable, Identifiable {
    var id = UUID()
    var date = Date.now
    let title: String
    let detail: String

    // Existing saved events predate structured model references. These are the stable
    // message formats emitted below; keep non-model lifecycle entries visible.
    var modelIDs: [String] {
        let selection: String
        switch title {
        case "Benchmark completed", "Benchmark excluded", "Model skipped", "Start failed", "Switch failed",
             "Forced recovery requested", "Forced recovery completed", "Command outcome uncertain", "Retrying model change":
            selection = detail.components(separatedBy: ": ").first ?? ""
        case "Model started", "Model switched", "Start requested", "Switch requested":
            selection = detail.components(separatedBy: ". ").first ?? ""
        case "Active selection changed":
            selection = String(detail.dropFirst("Observed ".count)).components(separatedBy: ". ").first ?? ""
        case "Previous selection restored":
            selection = detail
        default:
            return []
        }
        return selection.components(separatedBy: " → ").flatMap { $0.components(separatedBy: ", ") }
            .filter { !$0.isEmpty }
    }
}

struct AutopilotPendingChange: Codable {
    let model: String
    var start: Bool
    let reason: String
    var lastAttempt: Date?
    var firstAttempt: Date?
    var switchTimeouts: Int?
    var forceRestart: Bool?
    var replacedPID: Int?
    var replacedStartTimeMicros: Int64?
}

struct AutopilotSavedState: Codable {
    var benchmarks: [String: AutopilotBenchmark] = [:]
    var failures: [String: String] = [:]
    var calibrationSignature: String?
    var calibratedAt: Date?
    var recoveryModels: [String]?
    var economics = AutopilotEconomics()
    var events: [AutopilotEvent] = []
    var pendingChange: AutopilotPendingChange?
    var awaitingInitialSelection: Bool?
}

@MainActor @Observable
final class AutopilotController {
    static let shared = AutopilotController()
    private(set) var isEnabled = false
    private(set) var isBusy = false
    private(set) var status = "Paused"
    private(set) var lastError: String?
    private(set) var calibrationWarning: String?
    private var catalogModelIDs: Set<String> = []
    private(set) var localModels: [AutopilotLocalModel] = []
    private(set) var eligibilityExclusions: [String: String] = [:]
    private(set) var rankings: [AutopilotRank] = []
    private(set) var rankingExclusions: [String: String] = [:]
    private(set) var activeModels: [String] = []
    private(set) var lastEvaluation: Date?
    private(set) var nextEvaluation: Date?
    private(set) var consecutiveSamples = 0
    private(set) var saved = AutopilotSavedState()
    private var canRestoreCalibration = false
    private var samples: [AutopilotSample] = []
    private var settledPendingSelection: (models: [String], since: Date)?
    private var task: Task<Void, Never>?
    private var sleepTask: Task<Void, any Error>?
    private var servicesOverride: AutopilotServices?
    private let storageURL: URL

    var benchmarks: [String: AutopilotBenchmark] { saved.benchmarks }
    var events: [AutopilotEvent] {
        saved.events.filter { event in event.modelIDs.allSatisfy { catalogModelIDs.contains($0) } }
    }
    var bestModel: String? { rankings.first?.id }
    var economics: AutopilotEconomics { saved.economics }
    var memoryGB: Double { services.memoryGB }
    var canEnable: Bool { task == nil }
    private var services: AutopilotServices { servicesOverride ?? .live }

    init(storageURL: URL? = nil, services: AutopilotServices? = nil) {
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DarkbloomDashboard/autopilot.json")
        self.servicesOverride = services
        if let data = try? Data(contentsOf: self.storageURL) {
            do { saved = try JSONDecoder().decode(AutopilotSavedState.self, from: data) }
            catch { lastError = "Could not read saved calibration. Recalibration is required: \(error.localizedDescription)" }
        }
        if saved.recoveryModels != nil {
            status = "Calibration interrupted — enable to resume"
            lastError = "Inference may still be stopped from calibration. Enable Autopilot to finish calibration and start serving."
        }
        if let pending = saved.pendingChange {
            status = "Confirmation pending for \(pending.model) — enable to resume checking"
        }
    }

    func updateEconomics(_ value: AutopilotEconomics) {
        guard !isEnabled, !isBusy else { return }
        saved.economics = value
        samples = []
        rankings = []
        consecutiveSamples = 0
        persist()
    }

    func enable(recalibrate: Bool = false) {
        guard task == nil else { return }
        isEnabled = true
        canRestoreCalibration = false
        settledPendingSelection = nil
        rankings = []
        rankingExclusions = [:]
        lastEvaluation = nil
        lastError = nil
        samples = []
        consecutiveSamples = 0
        task = Task {
            var prepared = false
            while isEnabled {
                do {
                    if prepared {
                        try await evaluate()
                    } else {
                        try await prepare(recalibrate: recalibrate)
                        prepared = true
                    }
                } catch {
                    samples = []
                    consecutiveSamples = 0
                    let message = error.localizedDescription
                    // Once calibration may have stopped inference, do not repeat its
                    // destructive commands blindly. Ordinary preflight failures retry.
                    if !prepared, saved.recoveryModels != nil, saved.pendingChange == nil,
                       saved.awaitingInitialSelection != true {
                        lastError = message
                        record("Autopilot stopped", message)
                        isEnabled = false
                        await restoreAfterCalibration()
                        break
                    }
                    if lastError != message {
                        record("Evaluation skipped", message + " Retrying automatically; three fresh samples will be required.")
                    }
                    lastError = message
                }
                guard isEnabled else { break }
                if let pending = saved.pendingChange {
                    status = "Waiting for \(pending.model) confirmation — checking automatically"
                } else if lastError != nil {
                    status = "Waiting to retry automatically"
                } else {
                    status = "Monitoring"
                }
                let interval = services.evaluationInterval
                nextEvaluation = .now.addingTimeInterval(interval)
                let sleeper = Task { try await Task.sleep(for: .seconds(interval)) }
                sleepTask = sleeper
                try? await sleeper.value
                sleepTask = nil
                nextEvaluation = nil
            }
            isBusy = false
            nextEvaluation = nil
            status = lastError == nil ? "Paused" : "Needs attention"
            task = nil
        }
    }

    func pause() {
        guard isEnabled else { return }
        isEnabled = false
        status = isBusy ? "Pausing after the current command finishes" : "Paused"
        sleepTask?.cancel()
        samples = []
        consecutiveSamples = 0
        record("Autopilot paused", "No further decisions will run. An in-flight CLI command is allowed to finish safely.")
    }

    func pauseAndWait() async {
        pause()
        await task?.value
    }

    func refreshDisplay() async {
        guard !isEnabled, !isBusy else { return }
        do {
            try await refreshInventory()
            activeModels = try await daemonModels()
        }
        catch { lastError = error.localizedDescription }
    }

    private func refreshInventory() async throws {
        struct Inventory: Decodable { let models: [AutopilotLocalModel] }
        let output = try await services.command(["models", "list", "--all", "--json"])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let local = try decoder.decode(Inventory.self, from: Data(output.utf8)).models.sorted { $0.id < $1.id }
        let catalogOutput = try await services.command(["models", "catalog", "--json"])
        let catalog = try decoder.decode([AutopilotCatalogModel].self, from: Data(catalogOutput.utf8))
        // Publish only a complete snapshot. A failed catalog fetch must never use stale eligibility.
        catalogModelIDs = Set(catalog.map(\.id))
        localModels = local.filter { catalogModelIDs.contains($0.id) }
        eligibilityExclusions = AutopilotCatalogModel.exclusions(local: localModels, catalog: catalog, memoryGB: services.memoryGB)
        rankingExclusions = eligibilityExclusions
    }

    private func daemonModels() async throws -> [String] {
        guard let state = try await services.daemon() else { return [] }
        return state.selectedModels
    }

    private var calibratedEnvironment: (machineID: String, memoryGB: String, version: String)? {
        guard let signature = saved.calibrationSignature else { return nil }
        let parts = signature.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return (String(parts[0]), String(parts[1]), String(parts[2]))
    }

    private func calibrationMatchesMachine(_ backend: AutopilotServices) -> Bool {
        guard let environment = calibratedEnvironment else { return false }
        return environment.machineID == backend.machineID && environment.memoryGB == "\(backend.memoryGB)"
    }

    private func updateCalibrationWarning(version: String) {
        guard calibrationMatchesMachine(services), let environment = calibratedEnvironment,
              saved.calibratedAt != nil, environment.version != version else {
            calibrationWarning = nil
            return
        }
        let warning = "Darkbloom CLI version changed from \(environment.version) to \(version). Autopilot continues using the existing benchmarks. Recalibrate when convenient to refresh performance estimates."
        guard calibrationWarning != warning else { return }
        calibrationWarning = warning
        record("Recalibration recommended", warning)
    }

    private func prepare(recalibrate: Bool) async throws {
        isBusy = true
        defer { isBusy = false }
        // An accepted command may still be draining/loading, including after a
        // pause or app relaunch. Reconcile it before any calibration or new command.
        if saved.pendingChange != nil {
            try await refreshInventory()
            try await reconcilePendingChange()
            return
        }
        status = "Checking this Mac"
        let backend = services
        let version = try await backend.command(["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try await refreshInventory()
        activeModels = try await daemonModels()
        // Check credentials and network BEFORE taking a working provider offline.
        _ = try await backend.network()
        let signature = "\(backend.machineID)|\(backend.memoryGB)|\(version)"
        let matchesMachine = calibrationMatchesMachine(backend)
        updateCalibrationWarning(version: version)
        let resumeSelection = saved.awaitingInitialSelection == true &&
            matchesMachine && saved.calibratedAt != nil
        // CLI updates are advisory. Reuse complete measurements until the user
        // requests recalibration, including after pausing or relaunching Dashboard.
        let needsCalibration = !resumeSelection &&
            (recalibrate || !matchesMachine || saved.calibratedAt == nil || saved.recoveryModels != nil)
        if needsCalibration {
            let candidates = localModels.filter { eligibilityExclusions[$0.id] == nil }
            guard !candidates.isEmpty else {
                throw AutopilotError.message("No downloaded model is eligible in the current Darkbloom catalog for this Mac. Nothing was stopped.")
            }
            guard isEnabled else { return }
            if saved.recoveryModels == nil { saved.recoveryModels = activeModels }
            saved.awaitingInitialSelection = nil
            // Persist recovery intent before the stop command, including an empty prior selection.
            try save()
            status = "Stopping inference for calibration"
            record("Calibration started", "Stopping inference, then benchmarking \(candidates.count) eligible downloaded Darkbloom catalog models sequentially.")
            _ = try await backend.command(["stop"])
            canRestoreCalibration = true
            var stopped = false
            for _ in 0..<15 {
                if try await services.daemon() == nil { stopped = true; break }
                try await Task.sleep(for: .seconds(2))
            }
            guard stopped else { throw AutopilotError.message("The daemon did not stop after the CLI completed; calibration was not run.") }
            activeModels = []
            saved.calibratedAt = nil
            saved.calibrationSignature = nil
            calibrationWarning = nil
            saved.benchmarks = [:]
            saved.failures = eligibilityExclusions
            for id in eligibilityExclusions.keys.sorted() {
                record("Model skipped", "\(id): \(eligibilityExclusions[id]!)")
            }
            for (index, model) in candidates.enumerated() {
                guard isEnabled else { break }
                status = "Benchmarking \(index + 1)/\(candidates.count): \(model.id)"
                do {
                    let output = try await backend.command(["benchmark", "--model", model.id, "--iterations", "3", "--max-tokens", "256"])
                    let benchmark = try AutopilotBenchmark.parse(output, model: model)
                    saved.benchmarks[model.id] = benchmark
                    record("Benchmark completed", "\(model.id): \(benchmark.effectiveTokensPerSecond.formatted(.number.precision(.fractionLength(1)))) output tok/s including prefill; \(benchmark.totalSeconds.formatted()) seconds total.")
                } catch {
                    saved.failures[model.id] = error.localizedDescription
                    record("Benchmark excluded", "\(model.id): \(error.localizedDescription)")
                }
                try save()
            }
            guard isEnabled else { await restoreAfterCalibration(); return }
            guard !saved.benchmarks.isEmpty else { throw AutopilotError.message("No local model passed calibration.") }
            saved.calibrationSignature = signature
            saved.calibratedAt = .now
            saved.awaitingInitialSelection = true
            try save()
            // Exactly one fresh ranking pass after calibration, without the normal three-sample gate.
            try await initialSelection()
            saved.recoveryModels = nil
            saved.awaitingInitialSelection = nil
            try save()
            record("Calibration completed", "Measured \(saved.benchmarks.count) local models. Regular evaluations run every 60 seconds.")
        } else if isEnabled {
            if activeModels.isEmpty || resumeSelection {
                try await initialSelection()
                saved.recoveryModels = nil
                saved.awaitingInitialSelection = nil
                try save()
            }
            else { try await evaluate() }
        }
    }

    private func freshRanks() async throws -> [AutopilotRank] {
        try await refreshInventory()
        let network = try await services.network()
        let assessment = AutopilotRanking.assess(models: network.models, capacity: network.capacity,
                                     local: localModels.filter { eligibilityExclusions[$0.id] == nil }, benchmarks: saved.benchmarks,
                                     activeModels: Set(activeModels), memoryGB: services.memoryGB, economics: saved.economics)
        rankingExclusions = eligibilityExclusions.merging(assessment.exclusions) { _, latest in latest }
        return assessment.ranks
    }

    private func initialSelection() async throws {
        status = "Choosing the initial model"
        rankings = try await freshRanks()
        lastEvaluation = .now
        guard let best = rankings.first else { throw AutopilotError.message("No calibrated local model has current network pricing and capacity data.") }
        guard isEnabled else { await restoreAfterCalibration(); return }
        let reason = "Initial ranking: \(describe(best)). One pass is used after calibration or an explicit resume with inference stopped."
        // Once start is submitted, a timeout has an uncertain outcome. Avoid a competing restore.
        canRestoreCalibration = false
        try await changeModel(best.id, start: true, reason: reason)
        samples = []
        consecutiveSamples = 0
    }

    // Internal visibility allows deterministic tests without a live daemon or a 60-second wait.
    func evaluate(now: Date = .now) async throws {
        isBusy = true
        defer { isBusy = false }
        if saved.pendingChange != nil {
            try await reconcilePendingChange(now: now)
            return
        }
        status = "Evaluating network demand"
        let backend = services
        let version = try await backend.command(["--version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        updateCalibrationWarning(version: version)
        guard calibrationMatchesMachine(backend) else {
            throw AutopilotError.message("The saved calibration does not match this Mac or its memory. Pause and recalibrate to measure performance on this Mac.")
        }
        let state = try await services.daemon()
        let observed = state?.selectedModels ?? []
        if observed != activeModels {
            samples = []
            consecutiveSamples = 0
            record("Active selection changed", "Observed \(observed.joined(separator: ", ")). Restarting the sample window.")
        }
        activeModels = observed
        guard !observed.isEmpty else {
            guard state == nil else {
                throw AutopilotError.message("The running daemon has no selected models yet. Waiting for its selection.")
            }
            // A positively stopped daemon has no in-flight switch to conflict with.
            // Reuse the calibrated initial-selection path to restore serving.
            try await initialSelection()
            return
        }
        if let state, state.lifecycle != nil, !state.selectionIsSettled {
            throw AutopilotError.message("The daemon is changing its serving state. Waiting before making another model decision.")
        }
        let ranks = try await freshRanks()
        if let previous = samples.last, now.timeIntervalSince(previous.date) > 90 { samples = [] }
        samples.append(AutopilotSample(date: now, ranks: ranks))
        samples = Array(samples.suffix(3))
        rankings = AutopilotRanking.weighted(samples)
        for rank in ranks where !rankings.contains(where: { $0.id == rank.id }) {
            rankingExclusions[rank.id] = "Waiting for a complete window of consecutive samples"
        }
        lastEvaluation = now
        lastError = nil
        let winner = rankings.first?.id
        consecutiveSamples = samples.reversed().prefix(while: { $0.ranks.first?.id == winner && winner != nil }).count
        guard isEnabled else { return }
        let active: String?
        if observed.count == 1 {
            // Advertised selection is authoritative even while loaded slots lag.
            active = observed.first
        } else if let current = state?.currentModel, observed.contains(current) {
            // Several reported models still share one active inference model.
            active = current
        } else {
            // A lazy snapshot may have no current model. Compare against the best
            // measured selection rather than choosing an arbitrary model by name.
            active = rankings.first(where: { observed.contains($0.id) })?.id
        }
        guard let active, let candidate = AutopilotRanking.switchCandidate(samples: samples, active: active,
                                                               minimumImprovement: saved.economics.minimumImprovement) else { return }
        let current = rankings.first(where: { $0.id == active })!
        let reason = "Three consecutive samples agree (weights 1:2:3). \(describe(candidate)); current \(active): \(money(current.hourlyProfit))/h. Improvement exceeds \(Int(saved.economics.minimumImprovement * 100))% and $0.001/h."
        try await changeModel(candidate.id, start: false, reason: reason)
        samples = []
        consecutiveSamples = 0
    }

    private func changeModel(_ model: String, start: Bool, reason: String) async throws {
        guard isEnabled, saved.pendingChange == nil else { return }
        let pending = AutopilotPendingChange(model: model, start: start, reason: reason,
                                             lastAttempt: .now, firstAttempt: .now)
        saved.pendingChange = pending
        settledPendingSelection = nil
        // Persist before submitting: even a CLI error can have an uncertain outcome.
        do { try save() }
        catch { saved.pendingChange = nil; throw error }
        status = start ? "Starting \(model)" : "Switching to \(model)"
        record(start ? "Start requested" : "Switch requested", "\(activeModels.joined(separator: ", ")) → \(model). \(reason)")
        await submitPendingChange(pending)
        do { try await reconcilePendingChange() }
        catch {
            lastError = error.localizedDescription + " Autopilot will retry confirmation automatically."
            status = "Waiting for \(model) confirmation — checking automatically"
        }
    }

    private func submitPendingChange(_ pending: AutopilotPendingChange) async {
        guard isEnabled else { return }
        do {
            _ = try await services.command(AutopilotRecovery.command(for: pending))
        } catch {
            if !pending.start, pending.forceRestart != true {
                var updated = saved.pendingChange ?? pending
                if AutopilotRecovery.switchTimedOut(error) {
                    updated.switchTimeouts = (updated.switchTimeouts ?? 0) + 1
                    saved.pendingChange = updated
                    persist()
                }
                if AutopilotRecovery.switchIsBusy(error) || (updated.switchTimeouts ?? 0) >= 2 {
                    await forceRestart(updated, reason: error.localizedDescription)
                    return
                }
            }
            lastError = error.localizedDescription + " Autopilot will keep checking the daemon before issuing another change."
            record("Command outcome uncertain", "\(pending.model): \(lastError!)")
        }
    }

    private func forceRestart(_ pending: AutopilotPendingChange, reason: String, now: Date = .now) async {
        guard isEnabled else { return }
        let previousState = try? await services.daemon()
        guard isEnabled else { return }
        var recovery = pending
        recovery.forceRestart = true
        recovery.lastAttempt = now
        if let previousState {
            recovery.replacedPID = previousState.processIdentity.pid
            recovery.replacedStartTimeMicros = previousState.processIdentity.startTimeMicros
        }
        saved.pendingChange = recovery
        do { try save() }
        catch {
            saved.pendingChange = pending
            lastError = "Could not save forced recovery intent: \(error.localizedDescription). Retrying automatically."
            return
        }
        settledPendingSelection = nil
        samples = []
        consecutiveSamples = 0
        status = "Force-restarting provider with \(pending.model)"
        record("Forced recovery requested", "\(pending.model): \(reason)")
        // The previous CLI call has returned, releasing our lifecycle lease.
        // This path never recursively escalates another failed forced command.
        await submitPendingChange(recovery)
    }

    private func reconcilePendingChange(now: Date = .now) async throws {
        guard var pending = saved.pendingChange else { return }
        // Older saved intents may not have timestamps. Start a bounded recovery window.
        if pending.firstAttempt == nil {
            pending.firstAttempt = pending.lastAttempt ?? now
            pending.lastAttempt = pending.lastAttempt ?? now
            saved.pendingChange = pending
            try save()
        }
        status = "Waiting for \(pending.model) confirmation — checking automatically"
        let state: DarkbloomDaemonState?
        do { state = try await services.daemon() }
        catch {
            settledPendingSelection = nil
            let deadline = pending.forceRestart == true ? AutopilotRecovery.restartConfirmationInterval : AutopilotRecovery.maximumUnconfirmedInterval
            let since = pending.forceRestart == true ? pending.lastAttempt : (pending.firstAttempt ?? pending.lastAttempt)
            if now.timeIntervalSince(since ?? now) >= deadline {
                await forceRestart(pending, reason: "Daemon confirmation remains unavailable: \(error.localizedDescription)", now: now)
                return
            }
            throw error
        }
        let observed = state?.selectedModels ?? []
        activeModels = observed
        let transitioning = state?.lifecycle.map { $0.outcome != "serving" } ?? false
        let switchInProgress = state?.modelSwitch.map { !["serving", "switched"].contains($0.outcome) } ?? false
        let sameProcess = pending.replacedPID != nil && state?.processIdentity.pid == pending.replacedPID &&
            state?.processIdentity.startTimeMicros == pending.replacedStartTimeMicros
        let confirmed = observed == [pending.model] && !transitioning && !switchInProgress &&
            (pending.forceRestart != true || !sameProcess)
        if !confirmed, pending.forceRestart == true {
            if now.timeIntervalSince(pending.lastAttempt ?? now) >= AutopilotRecovery.restartConfirmationInterval {
                await forceRestart(pending, reason: "Replacement has not confirmed the intended model within three minutes.", now: now)
            }
            return
        }
        if !confirmed, now.timeIntervalSince(pending.firstAttempt ?? pending.lastAttempt ?? now) >= AutopilotRecovery.maximumUnconfirmedInterval {
            await forceRestart(pending, reason: "Model change has remained unconfirmed for 30 minutes.", now: now)
            return
        }
        // Probe the same target after our previous command has returned. A terminal
        // drain can reconcile gracefully; a wedged daemon rejects the probe as busy,
        // which escalates to forced replacement in submitPendingChange.
        let retrySwitch = !pending.start && state?.modelSwitch?.models == [pending.model] &&
            (["timedOut", "validating", "draining", "switching"].contains(state?.modelSwitch?.outcome ?? "") ||
             (state?.modelSwitch?.outcome == "failed" && observed == [pending.model]))
        let retryStart = state == nil
        if !confirmed, (retrySwitch || retryStart), isEnabled,
           now.timeIntervalSince(pending.lastAttempt ?? .distantPast) >= AutopilotRecovery.retryInterval {
            var retry = pending
            retry.start = pending.start || retryStart
            retry.firstAttempt = pending.firstAttempt ?? pending.lastAttempt ?? now
            retry.lastAttempt = now
            saved.pendingChange = retry
            do { try save() }
            catch { saved.pendingChange = pending; throw error }
            settledPendingSelection = nil
            record("Retrying model change", "\(pending.model): retrying after the previous command ended without confirmed service.")
            await submitPendingChange(retry)
            return
        }
        // An advertised selection is authoritative. Legacy snapshots retain the
        // loaded-model fallback, but known lifecycle transitions must finish first.
        if !confirmed {
            // A fresh, explicitly settled daemon serving another selection means the
            // command did not apply. Require two observations a minute apart before
            // allowing a new ranking window.
            guard let state, state.advertisedModels != nil, state.selectionIsSettled,
                  !observed.isEmpty else {
                settledPendingSelection = nil
                return
            }
            guard let previous = settledPendingSelection, previous.models == observed,
                  now.timeIntervalSince(previous.since) >= 60 else {
                if settledPendingSelection?.models != observed {
                    settledPendingSelection = (observed, now)
                }
                return
            }
        }
        saved.pendingChange = nil
        // A confirmed initial start also resolves interrupted calibration recovery.
        let previousRecovery = saved.recoveryModels
        let previousAwaitingSelection = saved.awaitingInitialSelection
        if pending.start {
            saved.recoveryModels = nil
            saved.awaitingInitialSelection = nil
        }
        do { try save() }
        catch {
            saved.pendingChange = pending
            saved.recoveryModels = previousRecovery
            saved.awaitingInitialSelection = previousAwaitingSelection
            throw error
        }
        samples = []
        consecutiveSamples = 0
        settledPendingSelection = nil
        lastError = nil
        status = "Monitoring"
        if confirmed {
            if pending.forceRestart == true {
                record("Forced recovery completed", "\(pending.model): the provider confirmed the intended selection after forced recovery.")
            }
            record(pending.start ? "Model started" : "Model switched", "\(pending.model). \(pending.reason)")
        } else {
            record("Change not applied", "Daemon is serving \(observed.joined(separator: ", ")). Resuming fresh evaluations before retrying a model change.")
        }
    }

    private func restoreAfterCalibration() async {
        guard canRestoreCalibration, let previous = saved.recoveryModels else { return }
        canRestoreCalibration = false
        guard !previous.isEmpty else {
            saved.recoveryModels = nil
            persist()
            return
        }
        status = "Restoring the previous selection"
        do {
            _ = try await services.command(["start"] + previous.flatMap { ["--model", $0] })
            activeModels = try await daemonModels()
            guard Set(activeModels) == Set(previous) else { throw AutopilotError.message("Previous selection has not yet been confirmed by the daemon.") }
            saved.recoveryModels = nil
            persist()
            record("Previous selection restored", previous.joined(separator: ", "))
        } catch {
            lastError = "Could not restore inference: \(error.localizedDescription). Recovery information is saved; check Local Service."
            record("Recovery needed", lastError!)
        }
    }

    private func describe(_ rank: AutopilotRank) -> String {
        "\(rank.id): \(money(rank.hourlyProfit))/h estimated net potential, \(Int(rank.utilization * 100))% estimated utilization, \(rank.demand) requests / \(rank.competitors) providers, \(rank.effectiveTPS.formatted(.number.precision(.fractionLength(1)))) effective output tok/s"
    }

    private func money(_ value: Double) -> String { value.formatted(.currency(code: "USD").precision(.fractionLength(4))) }

    private func record(_ title: String, _ detail: String) {
        saved.events.insert(AutopilotEvent(title: title, detail: detail), at: 0)
        saved.events = Array(saved.events.prefix(500))
        persist()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: storageURL, options: .atomic)
    }

    private func persist() {
        do { try save() }
        catch { lastError = "Could not save Autopilot history: \(error.localizedDescription)" }
    }
}
#endif
