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
        guard memory <= memoryGB * 0.8 else { return "Exceeds 80% of unified memory" }
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

    var hourlyCost: Double { max(0, electricityPerKWh) * max(0, servingWatts) / 1000 }
}

struct AutopilotRank: Identifiable, Sendable {
    let id: String
    let utilization: Double
    let effectiveTPS: Double
    let hourlyRevenue: Double
    let hourlyProfit: Double
    let demand: Int
    let competitors: Int
}

struct AutopilotSample: Sendable {
    let date: Date
    let ranks: [AutopilotRank]
}

/// A conservative single-request-slot estimate. Capacity snapshots cannot reveal actual
/// arrival rates, routing priority, request lengths, provider payouts or model-specific power.
/// Completion tokens / TOTAL benchmark time includes prefill and generation overhead.
/// Only completion revenue is counted: prompt/cache/request billing mix is unknown.
enum AutopilotRanking {
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
            let utilization = min(1, Double(supply.demand) / Double(providers))
            let revenue = benchmark.effectiveTokensPerSecond * price * 3600 * utilization
            guard revenue.isFinite else { return exclude("Invalid earning estimate") }
            return AutopilotRank(id: installed.id, utilization: utilization,
                                 effectiveTPS: benchmark.effectiveTokensPerSecond,
                                 hourlyRevenue: revenue, hourlyProfit: revenue - economics.hourlyCost,
                                 demand: supply.demand, competitors: providers)
        }.sorted { lhs, rhs in
            lhs.hourlyProfit == rhs.hourlyProfit ? lhs.id < rhs.id : lhs.hourlyProfit > rhs.hourlyProfit
        }
        return Assessment(ranks: ranks, exclusions: exclusions)
    }

    static func weighted(_ samples: [AutopilotSample]) -> [AutopilotRank] {
        guard let latest = samples.last else { return [] }
        // A missing observation invalidates a model's window; never fill missing demand with zero.
        return latest.ranks.compactMap { rank -> AutopilotRank? in
            let observations = samples.enumerated().compactMap { index, sample -> (Double, AutopilotRank)? in
                sample.ranks.first(where: { $0.id == rank.id }).map { (Double(index + 1), $0) }
            }
            guard observations.count == samples.count else { return nil }
            let weights = observations.reduce(0) { $0 + $1.0 }
            return AutopilotRank(id: rank.id, utilization: observations.reduce(0) { $0 + $1.0 * $1.1.utilization } / weights,
                                 effectiveTPS: rank.effectiveTPS,
                                 hourlyRevenue: observations.reduce(0) { $0 + $1.0 * $1.1.hourlyRevenue } / weights,
                                 hourlyProfit: observations.reduce(0) { $0 + $1.0 * $1.1.hourlyProfit } / weights,
                                 demand: rank.demand, competitors: rank.competitors)
        }.sorted { $0.hourlyProfit == $1.hourlyProfit ? $0.id < $1.id : $0.hourlyProfit > $1.hourlyProfit }
    }

    static func switchCandidate(samples: [AutopilotSample], active: String, minimumImprovement: Double) -> AutopilotRank? {
        guard samples.count == 3,
              zip(samples, samples.dropFirst()).allSatisfy({ newerPair in
                  let gap = newerPair.1.date.timeIntervalSince(newerPair.0.date)
                  return gap >= 55 && gap <= 90
              }),
              let best = weighted(samples).first, best.id != active, best.hourlyProfit > 0,
              let current = weighted(samples).first(where: { $0.id == active }),
              best.hourlyProfit > current.hourlyProfit + max(abs(current.hourlyProfit) * minimumImprovement, 0.001),
              samples.allSatisfy({ sample in
                  guard sample.ranks.first?.id == best.id,
                        let existing = sample.ranks.first(where: { $0.id == active }),
                        let contender = sample.ranks.first else { return false }
                  return contender.hourlyProfit > 0 && contender.hourlyProfit > existing.hourlyProfit
              }) else { return nil }
        return best
    }
}
