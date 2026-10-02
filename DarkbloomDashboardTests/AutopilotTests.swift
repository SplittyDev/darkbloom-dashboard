import Foundation
import Testing
@testable import DarkbloomDashboard

@MainActor
struct AutopilotTests {
    private func local(_ id: String = "fast", memory: Double = 10) -> AutopilotLocalModel {
        .init(id: id, estimatedMemoryGb: memory, sizeBytes: 100, templateRenderOk: true)
    }

    private func benchmark(_ id: String, seconds: Double = 10) -> AutopilotBenchmark {
        .init(modelID: id, measuredAt: .now, sizeBytes: 100, promptTokens: 20,
              completionTokens: 200, totalSeconds: seconds, decodeTokensPerSecond: 30)
    }

    private func capacity(_ id: String, demand: Int = 4, providers: Int = 4) -> DarkbloomModelCapacity {
        .init(id: id, canAccept: false, routableProviders: providers, warmProviders: providers,
              activeRequests: demand, queuedRequests: 0, queueLimit: 8, aggregateTps: 100)
    }

    private func model(_ id: String, price: String = "0.000001", artifactID: String? = nil) throws -> DarkbloomModelData {
        let json = """
        {"id":"\(id)","hugging_face_id":"\(artifactID ?? id)","object":"model","created":0,"owned_by":"test","name":"\(id)",
        "metadata":{"attested_providers":1,"can_accept":true,"display_name":"\(id)","model_type":"text",
        "provider_count":1,"quantization":"4bit","routable_providers":1,"trust_level":"hardware","warm_providers":1},
        "context_length":4096,"max_output_length":256,"input_modalities":["text"],"output_modalities":["text"],
        "pricing":{"completion":"\(price)","prompt":"0","image":"0","input_cache_read":"0","request":"0"}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(DarkbloomModelData.self, from: Data(json.utf8))
    }

    @Test func benchmarkParsingIncludesTotalTimeAndRejectsWrongModel() throws {
        let measurement = try AutopilotBenchmark.parse(report("fast"), model: local())
        #expect(measurement.effectiveTokensPerSecond == 20)
        #expect(measurement.decodeTokensPerSecond == 30)
        #expect(throws: (any Error).self) { try AutopilotBenchmark.parse(report("other"), model: local()) }
        #expect(throws: (any Error).self) { try AutopilotBenchmark.parse("Loading model: fast", model: local()) }
        #expect(throws: (any Error).self) { try AutopilotBenchmark.parse(report("fast").replacingOccurrences(of: "10000 ms", with: "0 ms"), model: local()) }
    }

    @Test func doublePriceDoesNotCompensateForTripleTotalTime() throws {
        // Existing saved share settings must be ignored: providers receive the full price.
        let legacyEconomics = try JSONDecoder().decode(AutopilotEconomics.self, from: Data(
            #"{"providerShare":0.5,"electricityPerKWh":0,"servingWatts":0,"minimumImprovement":0.1}"#.utf8))
        let ranks = AutopilotRanking.rank(models: try [model("fast"), model("slow", price: "0.000002")],
            capacity: [capacity("fast"), capacity("slow")], local: [local(), local("slow")],
            benchmarks: ["fast": benchmark("fast"), "slow": benchmark("slow", seconds: 30)],
            activeModels: ["fast"], memoryGB: 32, economics: legacyEconomics)
        #expect(ranks.first?.id == "fast")
        #expect(ranks.first?.hourlyRevenue == 0.072)
        #expect(ranks.last?.utilization == 0.8)
    }

    @Test func excludesMissingDownloadsOversizedModelsAndUnmeasuredModels() throws {
        let ranks = AutopilotRanking.rank(models: try [model("fast"), model("huge"), model("missing"), model("unmeasured")],
            capacity: [capacity("fast"), capacity("huge"), capacity("missing"), capacity("unmeasured")],
            local: [local(), local("huge", memory: 30), local("unmeasured")],
            benchmarks: ["fast": benchmark("fast"), "huge": benchmark("huge"), "missing": benchmark("missing")],
            activeModels: [], memoryGB: 32, economics: .init())
        #expect(ranks.map(\.id) == ["fast"])
    }

    @Test func gemmaPricingAliasJoinsItsLocalBenchmarkAndCapacity() throws {
        let gemma = "gemma-4-26b-qat-4bit"
        let gpt = "gpt-oss-20b"
        let assessment = AutopilotRanking.assess(
            models: try [model("gemma-4-26b", price: "0.00000022", artifactID: gemma), model(gpt, price: "0.00000009")],
            capacity: [capacity(gemma, demand: 191, providers: 562), capacity(gpt, demand: 246, providers: 535)],
            local: [local(gemma), local(gpt), local("gemma-4-26b-8bit")],
            benchmarks: [gemma: benchmark(gemma, seconds: 3.012), gpt: benchmark(gpt, seconds: 2.522),
                         "gemma-4-26b-8bit": benchmark("gemma-4-26b-8bit")],
            activeModels: [gpt], memoryGB: 128, economics: .init())
        #expect(assessment.ranks.first?.id == gemma)
        #expect(assessment.ranks.first?.competitors == 563)
        #expect(assessment.ranks.map(\.id).contains(gpt))
        #expect(assessment.exclusions[gemma] == nil)
        // Another quantization cannot inherit this price through a guessed name alias.
        #expect(assessment.exclusions["gemma-4-26b-8bit"] == "No network pricing entry for this local model")
    }

    @Test func rankingExplainsMissingCapacityAfterSuccessfulCalibration() throws {
        let assessment = AutopilotRanking.assess(models: try [model("fast")], capacity: [], local: [local()],
            benchmarks: ["fast": benchmark("fast")], activeModels: [], memoryGB: 32, economics: .init())
        #expect(assessment.ranks.isEmpty)
        #expect(assessment.exclusions["fast"] == "No current network capacity sample")
    }

    @Test func explicitAliasAlsoSupportsCatalogCapacityIDs() throws {
        let assessment = AutopilotRanking.assess(models: try [model("catalog-id", artifactID: "fast")],
            capacity: [capacity("catalog-id")], local: [local()], benchmarks: ["fast": benchmark("fast")],
            activeModels: ["fast"], memoryGB: 32, economics: .init())
        #expect(assessment.ranks.first?.id == "fast")
        #expect(assessment.ranks.first?.competitors == 4)
    }

    @Test func catalogEligibilityRequiresExactActiveTextModelsAndMinimumRAM() throws {
        let json = #"""
        [
          {"id":"fast","active":true,"model_type":"text","min_ram_gb":24},
          {"id":"inactive","active":false,"model_type":"text","min_ram_gb":24},
          {"id":"huge","active":true,"model_type":"text","min_ram_gb":64},
          {"id":"audio","active":true,"model_type":"audio","min_ram_gb":24}
        ]
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let catalog = try decoder.decode([AutopilotCatalogModel].self, from: Data(json.utf8))
        let excluded = AutopilotCatalogModel.exclusions(local: [local(), local("inactive"), local("huge"),
            local("audio"), local("mlx-community/fast")], catalog: catalog, memoryGB: 32)
        #expect(excluded["fast"] == nil)
        #expect(excluded["inactive"] == "Inactive in the Darkbloom model catalog")
        #expect(excluded["huge"]?.contains("64 GB") == true)
        #expect(excluded["audio"] != nil)
        #expect(excluded["mlx-community/fast"] == "Not in the Darkbloom model catalog")
    }

    @Test func noDemandHasNoRevenueAndPowerCanMakeProfitNegative() throws {
        let ranks = AutopilotRanking.rank(models: try [model("fast")], capacity: [capacity("fast", demand: 0)],
            local: [local()], benchmarks: ["fast": benchmark("fast")], activeModels: [], memoryGB: 32,
            economics: .init(electricityPerKWh: 0.2, servingWatts: 100))
        #expect(ranks.first?.hourlyRevenue == 0)
        #expect(abs((ranks.first?.hourlyProfit ?? 1) + 0.02) < 0.00001)
    }

    private func rank(_ id: String, _ profit: Double) -> AutopilotRank {
        .init(id: id, utilization: 1, effectiveTPS: 20, hourlyRevenue: profit,
              hourlyProfit: profit, demand: 4, competitors: 4)
    }

    private func window(_ profits: [Double], gap: Double = 60) -> [AutopilotSample] {
        profits.enumerated().map { index, value in
            .init(date: Date(timeIntervalSince1970: Double(index) * gap),
                  ranks: [rank("active", 1), rank("candidate", value)].sorted { $0.hourlyProfit > $1.hourlyProfit })
        }
    }

    @Test func needsThreeConsecutiveWinnersAndWeightedImprovement() {
        #expect(AutopilotRanking.switchCandidate(samples: window([2, 2]), active: "active", minimumImprovement: 0.1) == nil)
        #expect(AutopilotRanking.switchCandidate(samples: window([2, 0.5, 2]), active: "active", minimumImprovement: 0.1) == nil)
        #expect(AutopilotRanking.switchCandidate(samples: window([1.05, 1.05, 1.05]), active: "active", minimumImprovement: 0.1) == nil)
        #expect(AutopilotRanking.switchCandidate(samples: window([2, 2, 2]), active: "active", minimumImprovement: 0.1)?.id == "candidate")
        let weighted = AutopilotRanking.weighted(window([2, 3, 4])).first!
        #expect(abs(weighted.hourlyProfit - 20.0 / 6) < 0.00001)
    }

    @Test func staleRapidOrMissingSamplesCannotTriggerSwitches() {
        #expect(AutopilotRanking.switchCandidate(samples: window([2, 2, 2], gap: 120), active: "active", minimumImprovement: 0.1) == nil)
        #expect(AutopilotRanking.switchCandidate(samples: window([2, 2, 2], gap: 1), active: "active", minimumImprovement: 0.1) == nil)
        var samples = window([2, 2, 2])
        samples[1] = .init(date: samples[1].date, ranks: [rank("candidate", 2)])
        #expect(AutopilotRanking.switchCandidate(samples: samples, active: "active", minimumImprovement: 0.1) == nil)
        #expect(AutopilotRanking.switchCandidate(samples: window([2, 2, 2]), active: "unknown", minimumImprovement: 0.1) == nil)
    }

    private func report(_ id: String) -> String {
        """
        Benchmark: \(id)
        Iterations: 3
        Average:
          Prefill latency: 1000 ms
          Decode throughput: 30 tok/s
          Total time: 10000 ms
          Prompt tokens: 20
          Completion tokens: 200
        """
    }

    #if os(macOS)
    @Test(.timeLimit(.minutes(1))) func commandRunnerHandlesRepeatedImmediateExits() async throws {
        for _ in 0..<30 {
            let output = try await AutopilotCLI.run(executable: "/bin/echo", arguments: ["test-version"], timeout: 2)
            #expect(output == "test-version\n")
        }
        do {
            _ = try await AutopilotCLI.run(executable: "/bin/sh", arguments: ["-c", "echo failure >&2; exit 7"], timeout: 2)
            Issue.record("Expected command failure")
        } catch {
            #expect(error.localizedDescription.contains("failed (7): failure"))
        }
    }

    @Test func commandRunnerDrainsVerboseOutputAndBoundsRuntime() async throws {
        let output = try await AutopilotCLI.run(executable: "/bin/sh", arguments: ["-c",
            "i=0; while [ $i -lt 5000 ]; do echo output-line; echo error-line >&2; i=$((i+1)); done"], timeout: 10)
        #expect(output.split(separator: "\n").count == 5000)
        do {
            _ = try await AutopilotCLI.run(executable: "/bin/sh", arguments: ["-c", "exec /bin/sleep 5"], timeout: 0.1)
            Issue.record("Expected command timeout")
        } catch { #expect(error.localizedDescription.contains("timed out")) }
    }

    @Test func benchmarkConfigClearsOnlyBackendSelection() throws {
        let original = """
        [provider]
        name = "fixture"
        [backend]
        enabled_models = [
          "a]#b", # ] in a comment
          'second'
        ] # selection
        idle_timeout_mins = 4
        [gemma_optimizations]
        prefill_layer18 = false
        """
        let copy = try AutopilotCLI.benchmarkConfiguration(original)
        #expect(copy.contains("enabled_models = [] # selection"))
        #expect(copy.contains("idle_timeout_mins = 4"))
        #expect(copy.contains("prefill_layer18 = false"))
        #expect(try AutopilotCLI.benchmarkConfiguration("[backend]") == "[backend]\nenabled_models = []")
        #expect(try AutopilotCLI.benchmarkConfiguration("[backend]\nmodel = 'x'\n").contains("enabled_models = []\nmodel = 'x'"))
        #expect(throws: (any Error).self) { try AutopilotCLI.benchmarkConfiguration("[backend]\nenabled_models = [ 'x'") }
    }

    @Test func thirdSampleSwitchesWithoutRestartAndTimeoutKeepsMonitoring() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow", price: "0.000003")], report: report)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let saved = AutopilotSavedState(benchmarks: ["fast": benchmark("fast"), "slow": benchmark("slow")],
            calibrationSignature: "fixture|32.0|test-version", calibratedAt: .now)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: url)
        fixture.active = ["fast"]
        let controller = AutopilotController(storageURL: url, services: fixture.services)
        controller.enable()
        for _ in 0..<100 where controller.nextEvaluation == nil && !controller.canEnable { try await Task.sleep(for: .milliseconds(10)) }
        let first = try #require(controller.lastEvaluation)
        #expect(!fixture.commands.contains { $0.first == "switch" })
        try await controller.evaluate(now: first.addingTimeInterval(60))
        #expect(!fixture.commands.contains { $0.first == "switch" })
        try await controller.evaluate(now: first.addingTimeInterval(120))
        #expect(fixture.commands.filter { $0.first == "switch" } == [["switch", "--model", "slow"]])
        #expect(!fixture.commands.contains { $0.first == "stop" || $0.first == "start" })
        #expect(controller.events.contains { $0.title == "Model switched" && $0.detail.contains("Three consecutive") })
        await controller.pauseAndWait()

        fixture.active = ["fast"]
        fixture.failSwitch = true
        controller.enable()
        for _ in 0..<100 where controller.nextEvaluation == nil && !controller.canEnable { try await Task.sleep(for: .milliseconds(10)) }
        let next = try #require(controller.lastEvaluation)
        try await controller.evaluate(now: next.addingTimeInterval(60))
        try await controller.evaluate(now: next.addingTimeInterval(120))
        #expect(controller.isEnabled)
        #expect(controller.saved.pendingChange?.model == "slow")
        #expect(controller.events.contains { $0.title == "Command outcome uncertain" })
        let switches = fixture.commands.filter { $0.first == "switch" }.count
        fixture.active = ["slow"]
        try await controller.evaluate(now: next.addingTimeInterval(180))
        #expect(controller.saved.pendingChange == nil)
        #expect(controller.lastError == nil)
        #expect(fixture.commands.filter { $0.first == "switch" }.count == switches)
        await controller.pauseAndWait()
    }

    @Test func stopFailureNeverBenchmarksOrSubmitsACompetingStart() async throws {
        let fixture = Harness(models: try [model("fast")], report: report)
        fixture.failStop = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = AutopilotController(storageURL: url, services: fixture.services)
        controller.enable()
        for _ in 0..<100 where !controller.canEnable { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!controller.isEnabled)
        #expect(!fixture.commands.contains { $0.first == "benchmark" || $0.first == "start" })
        #expect(controller.saved.recoveryModels == ["original"])
    }

    @Test func calibrationSkipsNonCatalogDownloadsEvenWithValidTemplates() async throws {
        let fixture = Harness(models: try [model("fast")], report: report)
        fixture.extraLocalIDs = ["minishlab/potion-code-16M-v2", "aufklarer/Silero-VAD-v5-MLX", "mlx-community/fast"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = AutopilotController(storageURL: url, services: fixture.services)
        controller.enable()
        for _ in 0..<100 where controller.nextEvaluation == nil && !controller.canEnable { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.isEnabled)
        #expect(fixture.commands.filter { $0.first == "benchmark" }.map { $0[2] } == ["fast"])
        #expect(controller.rankings.map(\.id) == ["fast"])
        for id in fixture.extraLocalIDs {
            #expect(!controller.localModels.contains { $0.id == id })
            #expect(controller.eligibilityExclusions[id] == nil)
            #expect(controller.rankingExclusions[id] == nil)
            #expect(!controller.events.contains { $0.detail.contains(id) })
        }
        let catalogIndex = try #require(fixture.commands.firstIndex(of: ["models", "catalog", "--json"]))
        let stopIndex = try #require(fixture.commands.firstIndex(of: ["stop"]))
        #expect(catalogIndex < stopIndex)
        // A catalog removal must exclude an existing successful benchmark on the next evaluation.
        fixture.catalogIDs = []
        try await controller.evaluate()
        #expect(controller.rankings.isEmpty)
        #expect(controller.localModels.isEmpty)
        #expect(controller.rankingExclusions["fast"] == nil)
        #expect(!controller.events.contains { $0.modelIDs.contains("fast") })
        await controller.pauseAndWait()
    }

    @Test func pausedDisplayHidesLegacyNonCatalogCalibrationAndHistory() async throws {
        let fixture = Harness(models: try [model("fast")], report: report)
        fixture.extraLocalIDs = ["minishlab/potion-code-16M-v2", "mlx-community/fast"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let saved = AutopilotSavedState(events: [
            .init(title: "Benchmark completed", detail: "fast: 20 output tok/s"),
            .init(title: "Benchmark excluded", detail: "minishlab/potion-code-16M-v2: unsupported"),
            .init(title: "Benchmark completed", detail: "mlx-community/fast: 20 output tok/s"),
            .init(title: "Calibration completed", detail: "Finished")
        ])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: url)
        let controller = AutopilotController(storageURL: url, services: fixture.services)
        await controller.refreshDisplay()
        #expect(controller.localModels.map(\.id) == ["fast"])
        #expect(controller.events.map(\.title) == ["Benchmark completed", "Calibration completed"])
        #expect(controller.saved.events.count == 4) // Hide old irrelevant entries without erasing history.
        #expect(!fixture.commands.contains { ["stop", "benchmark", "start", "switch"].contains($0[0]) })
    }

    @Test func unavailableOrEmptyCatalogNeverStopsInference() async throws {
        for unavailable in [true, false] {
            let fixture = Harness(models: try [model("fast")], report: report)
            fixture.failCatalog = unavailable
            fixture.catalogIDs = []
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let controller = AutopilotController(storageURL: url, services: fixture.services)
            controller.enable()
            for _ in 0..<100 where controller.nextEvaluation == nil { try await Task.sleep(for: .milliseconds(10)) }
            #expect(controller.isEnabled)
            #expect(controller.lastError != nil)
            #expect(!fixture.commands.contains { ["stop", "benchmark", "start", "switch"].contains($0[0]) })
            #expect(fixture.active == ["original"])
            await controller.pauseAndWait()
        }
    }

    @Test func initialCalibrationStopsBenchmarksAndStartsAfterOneRankingPass() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow")], report: report)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = AutopilotController(storageURL: url, services: fixture.services)
        controller.enable()
        for _ in 0..<100 where controller.nextEvaluation == nil && !controller.canEnable {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.isEnabled)
        #expect(controller.activeModels == ["fast"])
        #expect(controller.benchmarks.count == 2)
        #expect(fixture.commands.filter { ["stop", "benchmark", "start", "switch"].contains($0.first ?? "") }.map { $0[0] } == ["stop", "benchmark", "benchmark", "start"])
        #expect(fixture.networkCalls == 2) // preflight, then the single post-calibration ranking pass
        await controller.pauseAndWait()
        #expect(controller.events.contains { $0.title == "Model started" })
        let restored = AutopilotController(storageURL: url, services: fixture.services)
        #expect(!restored.isEnabled)
        #expect(restored.benchmarks.count == 2)
        let previousCommands = fixture.commands.count
        restored.enable()
        for _ in 0..<100 where restored.nextEvaluation == nil && !restored.canEnable {
            try await Task.sleep(for: .milliseconds(10))
        }
        await restored.pauseAndWait()
        #expect(!fixture.commands.dropFirst(previousCommands).contains { $0.first == "stop" || $0.first == "benchmark" })
    }

    @Test func pausingRecalibrationInvalidatesPartialMeasurements() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow")], report: report)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let saved = AutopilotSavedState(benchmarks: ["fast": benchmark("fast")],
            calibrationSignature: "fixture|32.0|test-version", calibratedAt: .now)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: url)
        let controller = AutopilotController(storageURL: url, services: fixture.services)
        fixture.onBenchmark = { controller.pause() }
        controller.enable(recalibrate: true)
        for _ in 0..<100 where !controller.canEnable { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.saved.calibratedAt == nil)
        #expect(controller.saved.calibrationSignature == nil)
        #expect(fixture.active == ["original"])
        #expect(fixture.commands.filter { $0.first == "benchmark" }.count == 1)
    }

    @Test func failedCalibrationRestoresPreviousSelection() async throws {
        let fixture = Harness(models: try [model("fast")], report: report)
        fixture.failBenchmarks = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = AutopilotController(storageURL: url, services: fixture.services)
        controller.enable()
        for _ in 0..<100 where !controller.canEnable { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!controller.isEnabled)
        #expect(fixture.active == ["original"])
        #expect(controller.saved.calibratedAt == nil)
        #expect(controller.saved.events.contains { $0.title == "Previous selection restored" })
    }

    private func calibratedController(_ fixture: Harness, url: URL, pending: AutopilotPendingChange? = nil) throws -> AutopilotController {
        let saved = AutopilotSavedState(benchmarks: ["fast": benchmark("fast"), "slow": benchmark("slow")],
            calibrationSignature: "fixture|32.0|test-version", calibratedAt: .now, pendingChange: pending)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(saved).write(to: url)
        return AutopilotController(storageURL: url, services: fixture.services)
    }

    private func waitForEvaluation(_ controller: AutopilotController) async throws {
        for _ in 0..<100 where controller.nextEvaluation == nil && !controller.canEnable {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(controller.nextEvaluation != nil)
    }

    @Test(arguments: [false, true], [false, true])
    func multipleReportedModelsStillSwitchToSingleWinner(winnerAlreadySelected: Bool, reportsAdvertisedSelection: Bool) async throws {
        let fixture = Harness(models: try [model("fast", price: "0.000003"), model("slow"), model("extra")], report: report)
        // The current model is slow, while sorting the reported IDs puts another model first.
        fixture.active = winnerAlreadySelected ? ["slow", "fast"] : ["slow", "extra"]
        fixture.reportsAdvertisedSelection = reportsAdvertisedSelection
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        let first = try #require(controller.lastEvaluation)
        #expect(controller.isEnabled)
        #expect(controller.status == "Monitoring")
        #expect(controller.consecutiveSamples == 1)
        #expect(!fixture.commands.contains { $0.first == "switch" })
        try await controller.evaluate(now: first.addingTimeInterval(60))
        #expect(controller.consecutiveSamples == 2)
        #expect(!fixture.commands.contains { $0.first == "switch" })
        try await controller.evaluate(now: first.addingTimeInterval(120))
        #expect(fixture.commands.filter { $0.first == "switch" } == [["switch", "--model", "fast"]])
        #expect(controller.activeModels == ["fast"])
        #expect(controller.saved.pendingChange == nil)
        #expect(controller.isEnabled)
        #expect(controller.lastError == nil)
        #expect(controller.events.contains { $0.title == "Model switched" && $0.detail.contains("current slow:") })
        #expect(!fixture.commands.contains { ["stop", "benchmark", "start"].contains($0[0]) })
        try await controller.evaluate(now: first.addingTimeInterval(180))
        #expect(fixture.commands.filter { $0.first == "switch" }.count == 1)
        await controller.pauseAndWait()
    }

    @Test func cliUpdateWarnsWhileContinuingThreeSampleSwitches() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow", price: "0.000003")], report: report)
        fixture.active = ["fast"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        let first = try #require(controller.lastEvaluation)
        #expect(controller.calibrationWarning == nil)

        fixture.version = "updated-version"
        try await controller.evaluate(now: first.addingTimeInterval(60))
        #expect(controller.calibrationWarning?.contains("from test-version to updated-version") == true)
        #expect(controller.lastError == nil)
        #expect(controller.consecutiveSamples == 2)
        #expect(!fixture.commands.contains { $0.first == "switch" })
        try await controller.evaluate(now: first.addingTimeInterval(120))
        #expect(fixture.commands.filter { $0.first == "switch" } == [["switch", "--model", "slow"]])
        #expect(controller.isEnabled)
        #expect(controller.calibrationWarning != nil)
        #expect(controller.saved.calibrationSignature == "fixture|32.0|test-version")
        #expect(controller.lastError == nil)
        try await controller.evaluate(now: first.addingTimeInterval(180))
        #expect(controller.events.filter { $0.title == "Recalibration recommended" }.count == 1)
        #expect(!fixture.commands.contains { ["stop", "benchmark", "start"].contains($0[0]) })

        // Returning to the measured version resolves the advisory without recalibration.
        fixture.version = "test-version"
        try await controller.evaluate(now: first.addingTimeInterval(240))
        #expect(controller.calibrationWarning == nil)
        await controller.pauseAndWait()
    }

    @Test(arguments: [false, true]) func enablingAfterCLIUpdateReusesBenchmarksAndRecoversStoppedDaemon(stopped: Bool) async throws {
        let fixture = Harness(models: try [model("fast"), model("slow")], report: report)
        fixture.version = "updated-version"
        fixture.active = stopped ? [] : ["fast"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        #expect(controller.isEnabled)
        #expect(controller.lastError == nil)
        #expect(controller.calibrationWarning?.contains("updated-version") == true)
        #expect(controller.activeModels == ["fast"])
        #expect(controller.benchmarks.count == 2)
        #expect(controller.saved.calibrationSignature == "fixture|32.0|test-version")
        #expect(!fixture.commands.contains { ["stop", "benchmark"].contains($0[0]) })
        #expect(fixture.commands.filter { $0.first == "start" }.count == (stopped ? 1 : 0))
        await controller.pauseAndWait()

        let restored = AutopilotController(storageURL: url, services: fixture.services)
        restored.enable()
        try await waitForEvaluation(restored)
        #expect(restored.isEnabled)
        #expect(restored.calibrationWarning != nil)
        #expect(!fixture.commands.contains { ["stop", "benchmark"].contains($0[0]) })
        await restored.pauseAndWait()
    }

    @Test func explicitRecalibrationClearsCLIUpdateWarningAndMeasuresNewVersion() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow")], report: report)
        fixture.version = "updated-version"
        fixture.active = ["fast"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        #expect(controller.calibrationWarning != nil)
        await controller.pauseAndWait()

        controller.enable(recalibrate: true)
        try await waitForEvaluation(controller)
        #expect(controller.isEnabled)
        #expect(controller.lastError == nil)
        #expect(controller.calibrationWarning == nil)
        #expect(controller.saved.calibrationSignature == "fixture|32.0|updated-version")
        #expect(fixture.commands.filter { $0.first == "benchmark" }.count == 2)
        try await controller.evaluate()
        #expect(controller.calibrationWarning == nil)
        await controller.pauseAndWait()
    }

    @Test func advertisedSelectionConfirmsBeforeLazyLoadedSlotsChange() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow", price: "0.000003")], report: report)
        fixture.active = ["fast"]
        fixture.delayChanges = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        let first = try #require(controller.lastEvaluation)
        try await controller.evaluate(now: first.addingTimeInterval(60))
        try await controller.evaluate(now: first.addingTimeInterval(120))
        #expect(controller.saved.pendingChange?.model == "slow")
        fixture.advertisedSelection = ["slow"]
        fixture.switchOutcome = "switched"
        try await controller.evaluate(now: first.addingTimeInterval(180))
        #expect(fixture.active == ["fast"]) // Loaded slots still belong to the previous model.
        #expect(controller.activeModels == ["slow"])
        #expect(controller.saved.pendingChange == nil)
        #expect(controller.isEnabled)
        #expect(controller.events.contains { $0.title == "Model switched" })
        await controller.pauseAndWait()
    }

    @Test func pendingDrainSurvivesErrorsPauseAndRelaunchWithoutDuplicateCommands() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow", price: "0.000003")], report: report)
        fixture.active = ["fast"]
        fixture.delayChanges = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        let first = try #require(controller.lastEvaluation)
        try await controller.evaluate(now: first.addingTimeInterval(60))
        try await controller.evaluate(now: first.addingTimeInterval(120))
        fixture.lifecycleOutcome = "draining"
        fixture.switchOutcome = "draining"
        fixture.failDaemon = true
        do { try await controller.evaluate(); Issue.record("Expected missing snapshot") } catch { }
        fixture.failDaemon = false
        try await controller.evaluate(now: try #require(controller.saved.pendingChange?.lastAttempt).addingTimeInterval(30))
        #expect(controller.saved.pendingChange != nil)
        #expect(controller.isEnabled)
        await controller.pauseAndWait()
        let restored = AutopilotController(storageURL: url, services: fixture.services)
        restored.enable(recalibrate: true) // A pending command takes precedence over recalibration.
        try await waitForEvaluation(restored)
        #expect(restored.isEnabled)
        #expect(fixture.commands.filter { ["start", "switch", "stop"].contains($0[0]) }.count == 1)
        fixture.active = ["slow"]
        fixture.lifecycleOutcome = "serving"
        fixture.switchOutcome = "switched"
        try await restored.evaluate()
        #expect(restored.saved.pendingChange == nil)
        #expect(restored.consecutiveSamples == 0)
        #expect(restored.lastError == nil)
        await restored.pauseAndWait()
    }

    @Test func unappliedSwitchRecoversAndRequiresThreeNewSamplesBeforeRetrying() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow", price: "0.000003")], report: report)
        fixture.active = ["fast"]
        fixture.failSwitch = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        let first = try #require(controller.lastEvaluation)
        try await controller.evaluate(now: first.addingTimeInterval(60))
        try await controller.evaluate(now: first.addingTimeInterval(120))
        try await controller.evaluate(now: first.addingTimeInterval(180))
        #expect(controller.saved.pendingChange == nil)
        #expect(controller.isEnabled)
        #expect(controller.events.contains { $0.title == "Change not applied" })
        fixture.failSwitch = false
        try await controller.evaluate(now: first.addingTimeInterval(240))
        try await controller.evaluate(now: first.addingTimeInterval(300))
        #expect(fixture.commands.filter { $0[0] == "switch" }.count == 1)
        try await controller.evaluate(now: first.addingTimeInterval(360))
        #expect(fixture.commands.filter { $0[0] == "switch" }.count == 2)
        #expect(controller.activeModels == ["slow"])
        await controller.pauseAndWait()
    }

    @Test func startupAndMonitoringAutomaticallyRecoverFromNetworkAndSnapshotErrors() async throws {
        let fixture = Harness(models: try [model("fast")], report: report)
        fixture.active = ["fast"]
        fixture.failNetwork = true
        fixture.evaluationInterval = 0.02
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        #expect(controller.isEnabled)
        #expect(controller.lastError != nil)
        fixture.failNetwork = false
        for _ in 0..<100 where controller.lastEvaluation == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.lastEvaluation != nil)
        fixture.failDaemon = true
        for _ in 0..<100 where controller.lastError == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.isEnabled)
        #expect(controller.consecutiveSamples == 0)
        fixture.failDaemon = false
        for _ in 0..<100 where controller.lastError != nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.lastError == nil)
        #expect(!fixture.commands.contains { ["start", "switch", "stop"].contains($0[0]) })
        await controller.pauseAndWait()
    }

    @Test func terminalDrainTimeoutRetriesGracefullyAndThenResumesRanking() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow", price: "0.000003")], report: report)
        fixture.active = ["fast"]
        fixture.failSwitch = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        let first = try #require(controller.lastEvaluation)
        try await controller.evaluate(now: first.addingTimeInterval(60))
        try await controller.evaluate(now: first.addingTimeInterval(120))
        fixture.lifecycleOutcome = "timedOut"
        fixture.switchOutcome = "timedOut"
        fixture.switchSelection = ["slow"]
        fixture.failSwitch = false
        try await controller.evaluate(now: first.addingTimeInterval(180))
        #expect(controller.isEnabled)
        #expect(fixture.commands.filter { $0[0] == "switch" } == [
            ["switch", "--model", "slow"], ["switch", "--model", "slow"]
        ])
        try await controller.evaluate(now: first.addingTimeInterval(240))
        #expect(controller.saved.pendingChange == nil)
        #expect(controller.activeModels == ["slow"])
        #expect(controller.lastError == nil)
        try await controller.evaluate(now: first.addingTimeInterval(300))
        #expect(controller.consecutiveSamples == 1)
        await controller.pauseAndWait()
    }

    @Test func networkFailureAfterCalibrationRetriesSelectionWithoutBenchmarkingAgain() async throws {
        let fixture = Harness(models: try [model("fast")], report: report)
        fixture.failNetworkAfterPreflight = true
        fixture.evaluationInterval = 0.02
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = AutopilotController(storageURL: url, services: fixture.services)
        controller.enable(recalibrate: true)
        try await waitForEvaluation(controller)
        #expect(controller.isEnabled)
        #expect(controller.saved.awaitingInitialSelection == true)
        fixture.failNetworkAfterPreflight = false
        for _ in 0..<100 where controller.activeModels != ["fast"] { try await Task.sleep(for: .milliseconds(10)) }
        #expect(controller.activeModels == ["fast"])
        #expect(controller.saved.awaitingInitialSelection == nil)
        #expect(fixture.commands.filter { ["stop", "benchmark", "start"].contains($0[0]) }.map { $0[0] } == ["stop", "benchmark", "start"])
        await controller.pauseAndWait()
    }

    @Test func stoppedDaemonRestartsAndDelayedStartConfirmsWithoutDisabling() async throws {
        let fixture = Harness(models: try [model("fast")], report: report)
        fixture.active = ["fast"]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let controller = try calibratedController(fixture, url: url)
        controller.enable()
        try await waitForEvaluation(controller)
        fixture.active = []
        fixture.delayChanges = true
        try await controller.evaluate()
        #expect(controller.isEnabled)
        #expect(controller.saved.pendingChange?.start == true)
        fixture.active = ["fast"]
        try await controller.evaluate()
        #expect(controller.saved.pendingChange == nil)
        #expect(controller.activeModels == ["fast"])
        #expect(fixture.commands.filter { $0[0] == "start" }.count == 1)
        await controller.pauseAndWait()
    }

    @Test func busySwitchForcesIntendedModelAndConfirmsNewProvider() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow")], report: report)
        fixture.active = ["fast"]
        fixture.lifecycleOutcome = "draining"
        fixture.switchOutcome = "draining"
        fixture.switchSelection = ["slow"]
        fixture.failSwitch = true
        fixture.switchError = "darkbloom switch failed (64): Error: A provider model switch is already in progress; wait for its receipt before retrying.\nUsage: darkbloom <subcommand>"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Resume an earlier switch rather than submitting a competing model decision.
        let pending = AutopilotPendingChange(model: "slow", start: false, reason: "Earlier selection",
            lastAttempt: .now.addingTimeInterval(-61))
        let controller = try calibratedController(fixture, url: url, pending: pending)
        controller.enable()
        try await waitForEvaluation(controller)
        #expect(fixture.commands.filter { ["start", "switch"].contains($0[0]) } == [
            ["switch", "--model", "slow"], ["start", "--model", "slow", "--timeout", "0", "--force"]
        ])
        try await controller.evaluate()
        #expect(controller.saved.pendingChange == nil)
        #expect(controller.activeModels == ["slow"])
        #expect(fixture.processID == 2)
        #expect(controller.isEnabled)
        #expect(controller.saved.events.contains { $0.title == "Forced recovery completed" })
        #expect(!fixture.commands.contains { ["stop", "benchmark"].contains($0[0]) })
        await controller.pauseAndWait()
    }

    @Test func repeatedDrainTimeoutsEscalateAcrossRelaunch() async throws {
        let fixture = Harness(models: try [model("fast"), model("slow")], report: report)
        fixture.active = ["fast"]
        fixture.lifecycleOutcome = "timedOut"
        fixture.switchOutcome = "timedOut"
        fixture.switchSelection = ["slow"]
        fixture.failSwitch = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pending = AutopilotPendingChange(model: "slow", start: false, reason: "Earlier selection",
            lastAttempt: .now.addingTimeInterval(-61))
        let controller = try calibratedController(fixture, url: url, pending: pending)
        controller.enable()
        try await waitForEvaluation(controller)
        #expect(controller.saved.pendingChange?.switchTimeouts == 1)
        #expect(!fixture.commands.contains { $0.contains("--force") })
        await controller.pauseAndWait()
        let restored = AutopilotController(storageURL: url, services: fixture.services)
        restored.enable()
        try await waitForEvaluation(restored)
        let attempt = try #require(restored.saved.pendingChange?.lastAttempt)
        try await restored.evaluate(now: attempt.addingTimeInterval(61))
        #expect(fixture.commands.filter { $0.contains("--force") }.count == 1)
        try await restored.evaluate()
        #expect(restored.saved.pendingChange == nil)
        #expect(restored.isEnabled)
        await restored.pauseAndWait()
    }

    @Test func failedForcedRecoveryPersistsAndRetriesWithoutRestartStormOrStaleConfirmation() async throws {
        let fixture = Harness(models: try [model("slow")], report: report)
        fixture.active = ["slow"]
        fixture.lifecycleOutcome = "draining"
        fixture.switchOutcome = "draining"
        fixture.failSwitch = true
        fixture.switchError = "A provider model switch is already in progress"
        fixture.failForce = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pending = AutopilotPendingChange(model: "slow", start: false, reason: "Earlier selection",
            lastAttempt: .now.addingTimeInterval(-61))
        let controller = try calibratedController(fixture, url: url, pending: pending)
        controller.enable()
        try await waitForEvaluation(controller)
        #expect(controller.saved.pendingChange?.forceRestart == true)
        #expect(controller.isEnabled)
        #expect(controller.lastError?.contains("Lifecycle lease unavailable") == true)
        await controller.pauseAndWait()
        // The old process reporting the right model is not proof of replacement.
        fixture.lifecycleOutcome = "serving"
        fixture.switchOutcome = "serving"
        let restored = AutopilotController(storageURL: url, services: fixture.services)
        restored.enable()
        try await waitForEvaluation(restored)
        let attempt = try #require(restored.saved.pendingChange?.lastAttempt)
        try await restored.evaluate(now: attempt.addingTimeInterval(179))
        #expect(restored.saved.pendingChange != nil)
        #expect(fixture.commands.filter { $0.contains("--force") }.count == 1)
        fixture.failForce = false
        try await restored.evaluate(now: attempt.addingTimeInterval(180))
        #expect(fixture.commands.filter { $0.contains("--force") }.count == 2)
        try await restored.evaluate(now: attempt.addingTimeInterval(181))
        #expect(restored.saved.pendingChange == nil)
        #expect(restored.lastError == nil)
        #expect(restored.isEnabled)
        await restored.pauseAndWait()
    }

    @Test func pauseWhileBusySwitchReturnsPreventsForcedRestart() async throws {
        let fixture = Harness(models: try [model("slow")], report: report)
        fixture.active = ["slow"]
        fixture.lifecycleOutcome = "draining"
        fixture.switchOutcome = "draining"
        fixture.failSwitch = true
        fixture.switchError = "A provider model switch is already in progress"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pending = AutopilotPendingChange(model: "slow", start: false, reason: "Earlier selection",
            lastAttempt: .now.addingTimeInterval(-61))
        let controller = try calibratedController(fixture, url: url, pending: pending)
        fixture.onSwitch = { controller.pause() }
        controller.enable()
        for _ in 0..<100 where !controller.canEnable { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!controller.isEnabled)
        #expect(controller.saved.pendingChange != nil)
        #expect(!fixture.commands.contains { $0.contains("--force") })
        await controller.pauseAndWait()
    }

    @Test func unrelatedCommandFailureDoesNotImmediatelyForceRestart() async throws {
        let fixture = Harness(models: try [model("slow")], report: report)
        fixture.active = ["slow"]
        fixture.lifecycleOutcome = "draining"
        fixture.switchOutcome = "draining"
        fixture.failSwitch = true
        fixture.switchError = "Invalid model selection"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pending = AutopilotPendingChange(model: "slow", start: false, reason: "Earlier selection",
            lastAttempt: .now.addingTimeInterval(-61))
        let controller = try calibratedController(fixture, url: url, pending: pending)
        controller.enable()
        try await waitForEvaluation(controller)
        #expect(controller.isEnabled)
        #expect(!fixture.commands.contains { $0.contains("--force") })
        #expect(controller.saved.pendingChange?.switchTimeouts == nil)
        await controller.pauseAndWait()
    }

    @Test func missingDaemonConfirmationHasABoundedRecoveryWindow() async throws {
        let fixture = Harness(models: try [model("slow")], report: report)
        fixture.active = ["slow"]
        fixture.failDaemon = true
        fixture.failForce = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("autopilot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let pending = AutopilotPendingChange(model: "slow", start: false, reason: "Earlier selection",
            lastAttempt: .now.addingTimeInterval(-1801))
        let controller = try calibratedController(fixture, url: url, pending: pending)
        controller.enable()
        try await waitForEvaluation(controller)
        #expect(controller.saved.pendingChange?.forceRestart == true)
        #expect(fixture.commands.filter { $0.contains("--force") }.count == 1)
        #expect(controller.isEnabled)
        fixture.failDaemon = false
        fixture.failForce = false
        let attempt = try #require(controller.saved.pendingChange?.lastAttempt)
        fixture.lifecycleOutcome = "draining"
        try await controller.evaluate(now: attempt.addingTimeInterval(180))
        try await controller.evaluate(now: attempt.addingTimeInterval(181))
        #expect(controller.saved.pendingChange == nil)
        await controller.pauseAndWait()
    }

    @MainActor private final class Harness {
        var commands: [[String]] = []
        var version = "test-version"
        var networkCalls = 0
        var extraLocalIDs: [String] = []
        var catalogIDs: [String]?
        var failCatalog = false
        var active = ["original"]
        var onBenchmark: (() -> Void)?
        var failBenchmarks = false
        var failSwitch = false
        var switchError = "Model-switch drain deadline expired"
        var onSwitch: (() -> Void)?
        var failForce = false
        var processID = 1
        var failStop = false
        var failNetwork = false
        var failNetworkAfterPreflight = false
        var failDaemon = false
        var delayChanges = false
        var advertisedSelection: [String]?
        var reportsAdvertisedSelection = true
        var lifecycleOutcome = "serving"
        var switchOutcome: String? = "serving"
        var switchSelection: [String]?
        var evaluationInterval: TimeInterval = 60
        let models: [DarkbloomModelData]
        let report: (String) -> String
        init(models: [DarkbloomModelData], report: @escaping (String) -> String) {
            self.models = models
            self.report = report
        }
        var services: AutopilotServices {
            .init(command: { args in
                self.commands.append(args)
                switch args[0] {
                case "--version": return self.version
                case "models":
                    if args[1] == "catalog" {
                        if self.failCatalog { throw AutopilotError.message("Catalog unavailable") }
                        return "[" + (self.catalogIDs ?? self.models.map(\.id)).map {
                            "{\"id\":\"\($0)\",\"active\":true,\"model_type\":\"text\",\"min_ram_gb\":24}"
                        }.joined(separator: ",") + "]"
                    }
                    return "{\"models\":[" + (self.models.map(\.id) + self.extraLocalIDs).map {
                        "{\"id\":\"\($0)\",\"estimated_memory_gb\":10,\"size_bytes\":100,\"template_render_ok\":true}"
                    }.joined(separator: ",") + "]}"
                case "stop":
                    if self.failStop { throw AutopilotError.message("Drain timed out") }
                    self.active = []; return "Stopped"
                case "benchmark":
                    self.onBenchmark?()
                    if self.failBenchmarks { throw AutopilotError.message("Benchmark failed") }
                    return self.report(args[2])
                case "start", "switch":
                    if args[0] == "switch" {
                        self.onSwitch?()
                        if self.failSwitch { throw AutopilotError.message(self.switchError) }
                    }
                    if args.contains("--force"), self.failForce { throw AutopilotError.message("Lifecycle lease unavailable") }
                    if self.delayChanges { return "OK" }
                    self.active = args.indices.dropLast().filter { args[$0] == "--model" }.map { args[$0 + 1] }
                    if args.contains("--force") { self.processID += 1 }
                    self.switchOutcome = args[0] == "switch" ? "switched" : "serving"
                    self.lifecycleOutcome = "serving"
                    return "OK"
                default: throw AutopilotError.message("Unexpected command")
                }
            }, network: {
                self.networkCalls += 1
                if self.failNetwork || (self.failNetworkAfterPreflight && self.networkCalls > 1) {
                    throw AutopilotError.message("Network unavailable")
                }
                return (self.models, self.models.map { .init(id: $0.id, canAccept: true, routableProviders: 1,
                    warmProviders: 1, activeRequests: 3, queuedRequests: 0, queueLimit: 8, aggregateTps: 100) })
            }, daemon: {
                if self.failDaemon { throw AutopilotError.message("Snapshot unavailable") }
                guard let model = self.active.first else { return nil }
                return DarkbloomDaemonState(writtenAt: .now,
                    capacity: .init(gpuMemoryActiveGb: 10, gpuMemoryCacheGb: 0, totalMemoryGb: 32), schema: 1,
                    currentModel: model, trust: .init(status: "online", receivedAt: .now, reason: "", trustLevel: "hardware"),
                    pid: self.processID, version: "test-version", slots: self.active.map { .init(kvBackendRequested: "auto", mtpEnabled: false, kvBackend: "contiguous", mtpActive: false, model: $0) },
                    warmModels: self.active, startedAt: .now, processIdentity: .init(pid: self.processID, startTimeMicros: Int64(self.processID)),
                    stats: .init(usageGaps: 0, tokensGenerated: 0, requestsServed: 0), inferenceActive: true, attestationPublicKey: nil,
                    advertisedModels: self.reportsAdvertisedSelection ? (self.advertisedSelection ?? self.active) : nil,
                    modelSwitch: self.switchOutcome.map { .init(outcome: $0, models: self.switchSelection ?? self.advertisedSelection ?? self.active) },
                    lifecycle: .init(outcome: self.lifecycleOutcome))
            }, memoryGB: 32, machineID: "fixture", evaluationInterval: evaluationInterval)
        }
    }
    #endif
}
