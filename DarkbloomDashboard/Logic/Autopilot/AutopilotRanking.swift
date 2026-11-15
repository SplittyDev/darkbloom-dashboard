import Foundation

struct AutopilotLocalModel: Codable, Identifiable, Sendable {
    let id: String
    let estimatedMemoryGb: Double?
    let sizeBytes: Int64?
    let templateRenderOk: Bool?

    func exclusion(memoryGB: Double) -> String? {
        guard let memory = estimatedMemoryGb, memory.isFinite, memory > 0 else {
            return "Memory requirement unavailable"
        }
        guard memory <= memoryGB else { return "Exceeds unified memory" }
        guard templateRenderOk == true else { return "No validated chat template" }
        return nil
    }
}

struct AutopilotBenchmark: Codable, Sendable {
    let modelID: String
    let measuredAt: Date
    let sizeBytes: Int64?
    let promptTokens: Double
    let completionTokens: Double
    let totalSeconds: Double
    let decodeTokensPerSecond: Double

    var effectiveTokensPerSecond: Double { completionTokens / totalSeconds }

    // Standard CLI report, verified against ProviderBenchmark/ModelBenchmark.swift.
    // Parse the final Average block only; never infer throughput from partial output.
    static func parse(_ output: String, model: AutopilotLocalModel) throws -> Self {
        guard output.contains("Benchmark: \(model.id)\n"),
              let average = output.components(separatedBy: "Average:").last,
              output.contains("Average:") else { throw AutopilotError.message("Missing benchmark report for \(model.id).") }
        func number(_ label: String) throws -> Double {
            guard let line = average.split(separator: "\n").first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(label) }),
                  let text = line.split(separator: ":", maxSplits: 1).last?.split(whereSeparator: \.isWhitespace).first,
                  let value = Double(text), value.isFinite, value >= 0 else {
                throw AutopilotError.message("Invalid benchmark field: \(label)")
            }
            return value
        }
        let result = try Self(modelID: model.id, measuredAt: .now, sizeBytes: model.sizeBytes,
                              promptTokens: number("Prompt tokens:"), completionTokens: number("Completion tokens:"),
                              totalSeconds: number("Total time:") / 1000,
                              decodeTokensPerSecond: number("Decode throughput:"))
        guard result.totalSeconds > 0, result.completionTokens > 0, result.decodeTokensPerSecond > 0 else {
            throw AutopilotError.message("Benchmark produced no usable tokens for \(model.id).")
        }
        return result
    }
}

enum AutopilotError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { value } else { nil } }
}

struct AutopilotEconomics: Codable, Equatable, Sendable {
    var electricityPerKWh: Double = 0
    var servingWatts: Double = 0
    var minimumImprovement: Double = 0.1

    // Optional for compatibility with existing saved economics. Zero excludes baseline
    // machine power until the user supplies an idle-power assumption.
    var idleWatts: Double?

    var idlePowerInput: Double {
        get { idleWatts ?? 0 }
        set { idleWatts = newValue }
    }

    private var idlePower: Double { idleWatts.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0 }
    var additionalServingWatts: Double {
        max(0, (servingWatts.isFinite ? servingWatts : 0) - idlePower)
    }
    var electricityRate: Double { electricityPerKWh.isFinite ? max(0, electricityPerKWh) : 0 }

    func averageWatts(utilization: Double) -> Double {
        idlePower + additionalServingWatts * min(1, max(0, utilization))
    }

    func hourlyCost(utilization: Double) -> Double {
        electricityRate * averageWatts(utilization: utilization) / 1000
    }
}

struct AutopilotLoadingLimits: Codable, Equatable, Sendable {
    var maximumModelCount: Int = 3
    // nil follows half of this machine's memory, including for legacy saved state.
    var maximumMemoryGB: Double?

    func normalized(memoryGB: Double) -> Self {
        let upper = max(1, memoryGB)
        let requested = maximumMemoryGB ?? memoryGB * 0.5
        return Self(maximumModelCount: min(3, max(1, maximumModelCount)),
                    maximumMemoryGB: min(upper, max(1, requested.isFinite ? requested : memoryGB * 0.5)))
    }
}

struct AutopilotRank: Identifiable, Sendable {
    let id: String
    let utilization: Double
    let effectiveTPS: Double
    let hourlyRevenue: Double
    let hourlyProfit: Double
    let demand: Int
    let competitors: Int
    var fullUtilizationRevenue: Double? = nil
    var busyHourRevenue: Double { fullUtilizationRevenue ?? (utilization > 0 ? hourlyRevenue / utilization : 0) }
    var offeredUtilization: Double? = nil
    var offeredRequestsPerHour: Double? = nil
    var requestSeconds: Double? = nil
    var requestPromptTokens: Double? = nil
    var requestCompletionTokens: Double? = nil
    var usesFleetThroughput = false

    var handledRequestsPerHour: Double? {
        guard let offeredRequestsPerHour, let requestSeconds else { return nil }
        return min(offeredRequestsPerHour, 3600 / requestSeconds)
    }
}

struct AutopilotSetEstimate: Sendable {
    let utilization: Double
    let averageWatts: Double
    let hourlyRevenue: Double
    let hourlyCost: Double
    let handledRequestsPerHour: Double?
    var hourlyProfit: Double { hourlyRevenue - hourlyCost }
}

struct AutopilotSample: Sendable {
    let date: Date
    let ranks: [AutopilotRank]
}

/// A single-request-slot estimate with equal provider shares and benchmark-sized requests.
/// Occupancy and rated fleet TPS imply an arrival rate; they do not measure arrivals.
/// Routing priority, real request lengths and model-specific power remain unknown.
/// Completion tokens / TOTAL benchmark time includes prefill and generation overhead.
/// Only completion revenue is counted: prompt/cache/request billing mix is unknown.
enum AutopilotRanking {
    /// One sequential engine: scale offered work proportionally when total busy
    /// time exceeds an hour. Electricity includes idle power only once for the set.
    static func estimate(_ ranks: [AutopilotRank], economics: AutopilotEconomics) -> AutopilotSetEstimate {
        let totalLoad = ranks.reduce(0) { $0 + max(0, $1.offeredUtilization ?? $1.utilization) }
        let scale = 1 / max(1, totalLoad)
        let busy = min(1, totalLoad)
        let revenue = ranks.reduce(0.0) { sum, rank in
            return sum + rank.busyHourRevenue * max(0, rank.offeredUtilization ?? rank.utilization) * scale
        }
        let requests = ranks.allSatisfy { $0.offeredRequestsPerHour != nil }
            ? ranks.reduce(0.0) { $0 + ($1.offeredRequestsPerHour ?? 0) * scale } : nil
        return .init(utilization: busy, averageWatts: economics.averageWatts(utilization: busy),
                     hourlyRevenue: revenue, hourlyCost: economics.hourlyCost(utilization: busy),
                     handledRequestsPerHour: requests)
    }

    /// Fill spare residency only when it improves the shared machine estimate.
    /// A model need not cover the machine's baseline idle cost by itself.
    static func selection(ranks: [AutopilotRank], local: [AutopilotLocalModel],
                          limits: AutopilotLoadingLimits, memoryGB: Double,
                          economics: AutopilotEconomics = .init()) -> [AutopilotRank] {
        let limits = limits.normalized(memoryGB: memoryGB)
        var remaining = limits.maximumMemoryGB!
        var result: [AutopilotRank] = []
        for rank in ranks {
            guard result.count < limits.maximumModelCount,
                  !result.contains(where: { $0.id == rank.id }),
                  let memory = local.first(where: { $0.id == rank.id })?.estimatedMemoryGb,
                  memory.isFinite, memory > 0, memory <= remaining else { continue }
            if !result.isEmpty {
                let before = estimate(result, economics: economics).hourlyProfit
                let after = estimate(result + [rank], economics: economics).hourlyProfit
                guard after > before + 1e-9 else { continue }
            }
            result.append(rank)
            remaining -= memory
        }
        return result
    }

    static func selectionFits(_ models: [String], local: [AutopilotLocalModel],
                              limits: AutopilotLoadingLimits, memoryGB: Double) -> Bool {
        let limits = limits.normalized(memoryGB: memoryGB)
        guard models.count <= limits.maximumModelCount else { return false }
        var total = 0.0
        for id in Set(models) {
            guard let memory = local.first(where: { $0.id == id })?.estimatedMemoryGb,
                  memory.isFinite, memory > 0 else { return false }
            total += memory
        }
        return total <= limits.maximumMemoryGB!
    }

    static func selectionExceedsLimits(_ models: [String], local: [AutopilotLocalModel],
                                       limits: AutopilotLoadingLimits, memoryGB: Double) -> Bool {
        let limits = limits.normalized(memoryGB: memoryGB)
        let knownMemory = local.filter { models.contains($0.id) }.compactMap(\.estimatedMemoryGb)
            .filter { $0.isFinite && $0 > 0 }.reduce(0, +)
        return Set(models).count > limits.maximumModelCount || knownMemory > limits.maximumMemoryGB!
    }

    static func switchSelection(samples: [AutopilotSample], active: [String], local: [AutopilotLocalModel],
                                limits: AutopilotLoadingLimits, memoryGB: Double,
                                minimumImprovement: Double, economics: AutopilotEconomics = .init()) -> [AutopilotRank]? {
        guard samples.count == 3,
              zip(samples, samples.dropFirst()).allSatisfy({
                  (55...90).contains($0.1.date.timeIntervalSince($0.0.date))
              }) else { return nil }
        let weighted = weighted(samples, economics: economics)
        let target = selection(ranks: weighted, local: local, limits: limits, memoryGB: memoryGB, economics: economics)
        let ids = Set(target.map(\.id))
        guard !target.isEmpty, ids != Set(active),
              samples.allSatisfy({ Set(selection(ranks: $0.ranks, local: local, limits: limits,
                                                  memoryGB: memoryGB, economics: economics).map(\.id)) == ids }) else { return nil }
        // A configured limit takes precedence over profitability or missing observations.
        if selectionExceedsLimits(active, local: local, limits: limits, memoryGB: memoryGB) { return target }
        guard estimate(target, economics: economics).hourlyProfit > 0 else { return nil }
        let removed = Set(active).subtracting(ids)
        func improvement(_ ranks: [AutopilotRank], margin: Double) -> Bool {
            let previous = ranks.filter { active.contains($0.id) }
            let proposed = ranks.filter { ids.contains($0.id) }
            guard previous.count == Set(active).count, proposed.count == ids.count else { return false }
            let current = estimate(previous, economics: economics).hourlyProfit
            let candidate = estimate(proposed, economics: economics).hourlyProfit
            let required = removed.isEmpty || margin == 0 ? 1e-9 : max(abs(current) * margin, 0.001)
            return candidate > current + required
        }
        guard improvement(weighted, margin: minimumImprovement),
              samples.allSatisfy({ improvement($0.ranks, margin: 0) }) else { return nil }
        return target
    }

    static func rank(models: [DarkbloomModelData], capacity: [DarkbloomModelCapacity],
                     local: [AutopilotLocalModel], benchmarks: [String: AutopilotBenchmark],
                     activeModels: Set<String>, memoryGB: Double, economics: AutopilotEconomics) -> [AutopilotRank] {
        assess(models: models, capacity: capacity, local: local, benchmarks: benchmarks,
               activeModels: activeModels, memoryGB: memoryGB, economics: economics).ranks
    }

    struct Assessment {
        let ranks: [AutopilotRank]
        let exclusions: [String: String]
    }

    static func assess(models: [DarkbloomModelData], capacity: [DarkbloomModelCapacity],
                       local: [AutopilotLocalModel], benchmarks: [String: AutopilotBenchmark],
                       activeModels: Set<String>, memoryGB: Double, economics: AutopilotEconomics) -> Assessment {
        var exclusions: [String: String] = [:]
        let ranks = local.compactMap { installed -> AutopilotRank? in
            func exclude(_ reason: String) -> AutopilotRank? {
                exclusions[installed.id] = reason
                return nil
            }
            if let reason = installed.exclusion(memoryGB: memoryGB) { return exclude(reason) }
            guard let benchmark = benchmarks[installed.id] else { return exclude("No successful local benchmark") }
            guard benchmark.sizeBytes == installed.sizeBytes else { return exclude("Download changed since calibration") }
            guard benchmark.totalSeconds.isFinite, benchmark.totalSeconds > 0,
                  benchmark.effectiveTokensPerSecond.isFinite, benchmark.effectiveTokensPerSecond > 0 else {
                return exclude("Invalid benchmark throughput")
            }
            // Pricing uses API-facing IDs, while capacity and the CLI can use artifact IDs.
            // Follow only explicit catalog mappings; never guess aliases by stripping quantization.
            let exact = models.filter { $0.id == installed.id }
            let matches = exact.isEmpty ? models.filter { $0.huggingFaceId == installed.id } : exact
            guard matches.count == 1, let model = matches.first else {
                return exclude(matches.isEmpty ? "No network pricing entry for this local model" : "Ambiguous network pricing identity")
            }
            guard let price = Double(model.pricing.completion), price.isFinite, price > 0 else {
                return exclude("No positive completion price")
            }
            guard let supply = capacity.first(where: { $0.id == installed.id })
                    ?? capacity.first(where: { $0.id == model.id }) else {
                return exclude("No current network capacity sample")
            }
            guard supply.activeRequests >= 0, supply.queuedRequests >= 0, supply.routableProviders >= 0 else {
                return exclude("Invalid network capacity sample")
            }
            // Preserve the local CLI ID throughout ranking, active comparisons and switching.
            let providers = max(1, supply.routableProviders + (activeModels.contains(installed.id) ? 0 : 1))
            // Rated fleet TPS is capacity, not actual token traffic. Approximate a
            // fleet request's total service time by scaling this benchmark's decode
            // rate, retaining its measured prefill/overhead ratio. Little's Law then
            // gives λ ≈ active / fleet request seconds. Share arrivals equally.
            let hasFleetRate = supply.routableProviders > 0 && supply.aggregateTps.isFinite && supply.aggregateTps > 0 &&
                benchmark.decodeTokensPerSecond.isFinite && benchmark.decodeTokensPerSecond > 0
            let fleetRequestSeconds = hasFleetRate
                ? benchmark.totalSeconds * benchmark.decodeTokensPerSecond /
                    (supply.aggregateTps / Double(supply.routableProviders))
                : benchmark.totalSeconds
            guard fleetRequestSeconds.isFinite, fleetRequestSeconds > 0 else { return exclude("Invalid fleet service-time estimate") }
            // The queue is a one-off backlog spread over the next evaluation minute,
            // rather than treating every queued request as permanent hourly demand.
            let arrivalRate = (Double(supply.activeRequests) / fleetRequestSeconds +
                Double(supply.queuedRequests) / 60) / Double(providers)
            let offeredUtilization = arrivalRate * benchmark.totalSeconds
            let utilization = min(1, offeredUtilization)
            let revenue = benchmark.effectiveTokensPerSecond * price * 3600 * utilization
            guard revenue.isFinite, offeredUtilization.isFinite else { return exclude("Invalid earning estimate") }
            return AutopilotRank(id: installed.id, utilization: utilization,
                                 effectiveTPS: benchmark.effectiveTokensPerSecond,
                                 hourlyRevenue: revenue, hourlyProfit: revenue - economics.hourlyCost(utilization: utilization),
                                 demand: supply.demand, competitors: providers,
                                 fullUtilizationRevenue: benchmark.effectiveTokensPerSecond * price * 3600,
                                 offeredUtilization: offeredUtilization, offeredRequestsPerHour: arrivalRate * 3600,
                                 requestSeconds: benchmark.totalSeconds, requestPromptTokens: benchmark.promptTokens,
                                 requestCompletionTokens: benchmark.completionTokens, usesFleetThroughput: hasFleetRate)
        }.sorted { lhs, rhs in
            lhs.hourlyProfit == rhs.hourlyProfit ? lhs.id < rhs.id : lhs.hourlyProfit > rhs.hourlyProfit
        }
        return Assessment(ranks: ranks, exclusions: exclusions)
    }

    static func weighted(_ samples: [AutopilotSample], economics: AutopilotEconomics = .init()) -> [AutopilotRank] {
        guard let latest = samples.last else { return [] }
        // A missing observation invalidates a model's window; never fill missing demand with zero.
        return latest.ranks.compactMap { rank -> AutopilotRank? in
            let observations = samples.enumerated().compactMap { index, sample -> (Double, AutopilotRank)? in
                sample.ranks.first(where: { $0.id == rank.id }).map { (Double(index + 1), $0) }
            }
            guard observations.count == samples.count else { return nil }
            let weights = observations.reduce(0) { $0 + $1.0 }
            let offered = observations.reduce(0) { $0 + $1.0 * ($1.1.offeredUtilization ?? $1.1.utilization) } / weights
            let utilization = min(1, offered)
            let fullRevenue = observations.reduce(0) { $0 + $1.0 * $1.1.busyHourRevenue } / weights
            let revenue = fullRevenue * utilization
            return AutopilotRank(id: rank.id, utilization: utilization,
                                 effectiveTPS: rank.effectiveTPS, hourlyRevenue: revenue,
                                 hourlyProfit: revenue - economics.hourlyCost(utilization: utilization),
                                 demand: rank.demand, competitors: rank.competitors,
                                 fullUtilizationRevenue: fullRevenue, offeredUtilization: offered,
                                 offeredRequestsPerHour: rank.offeredRequestsPerHour == nil ? nil :
                                     observations.reduce(0) { $0 + $1.0 * ($1.1.offeredRequestsPerHour ?? 0) } / weights,
                                 requestSeconds: rank.requestSeconds, requestPromptTokens: rank.requestPromptTokens,
                                 requestCompletionTokens: rank.requestCompletionTokens,
                                 usesFleetThroughput: observations.allSatisfy { $0.1.usesFleetThroughput })
        }.sorted { $0.hourlyProfit == $1.hourlyProfit ? $0.id < $1.id : $0.hourlyProfit > $1.hourlyProfit }
    }

}
