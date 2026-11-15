#if os(macOS)
import SwiftUI

struct AutopilotTab: View {
    @State private var controller = AutopilotController.shared
    @Environment(LocalServiceController.self) private var localService

    private var active: String {
        if let state = localService.daemonState, localService.processIsRunning == true,
           abs(state.writtenAt.timeIntervalSinceNow) < 30 {
            return state.selectedModels.joined(separator: ", ")
        }
        if localService.processIsRunning == false { return "Not serving" }
        return "Waiting for a fresh daemon snapshot"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Selected Models", value: active)
                LabeledContent("Loaded / Warm Models", value: loaded)
                LabeledContent("Best Model Set", value: controller.bestModels.isEmpty
                    ? "Awaiting calibration and fresh demand" : controller.bestModels.joined(separator: ", "))
                LabeledContent("Status") {
                    HStack {
                        Text(controller.status)
                            .contentTransition(.interpolate)
                        if controller.isBusy {
                            ProgressView().controlSize(.small)
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.interactiveSpring, value: controller.status)
                .animation(.interactiveSpring, value: controller.isBusy)
                LabeledContent("Actions") {
                    HStack {
                        if controller.isEnabled {
                            Button("Pause Autopilot") { controller.pause() }
                        } else {
                            Button(controller.saved.calibratedAt == nil ? "Calibrate & Enable" : "Enable Autopilot") {
                                controller.enable()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!controller.canEnable)
                        }
                        Button("Recalibrate & Enable") { controller.enable(recalibrate: true) }
                            .disabled(!controller.canEnable || controller.saved.calibratedAt == nil)
                    }
                }
            } header: {
                Text("Autopilot")
            } footer: {
                if let warning = controller.calibrationWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).textSelection(.enabled)
                }
                if let error = controller.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange).textSelection(.enabled)
                }
            }

            Section("Decision Window") {
                LabeledContent("Consecutive Winning Set Samples", value: "\(controller.consecutiveSamples) / 3")
                LabeledContent("Last / Next Evaluation") {
                    HStack {
                        if let date = controller.lastEvaluation {
                            Text(date, style: .time)
                                .transition(.opacity)
                        }
                        if let date = controller.nextEvaluation {
                            if controller.lastEvaluation != nil {
                                Text(verbatim: "/")
                                    .transition(.opacity)
                            }
                            Text(date, style: .relative)
                                .transition(.opacity)
                        }
                    }
                    .contentTransition(.interpolate)
                    .animation(.interactiveSpring, value: controller.lastEvaluation)
                    .animation(.interactiveSpring, value: controller.nextEvaluation)
                }
            }

            Section {
                Picker("Maximum Loaded Model Count", selection: Binding(get: {
                    controller.loadingLimits.maximumModelCount
                }, set: { value in
                    var limits = controller.loadingLimits
                    limits.maximumModelCount = value
                    controller.updateLoadingLimits(limits)
                })) {
                    ForEach(1...3, id: \.self) { Text("\($0)").tag($0) }
                }
                LabeledContent("Maximum Memory Threshold (GB)") {
                    TextField("Maximum Memory Threshold", value: Binding(get: {
                        controller.loadingLimits.maximumMemoryGB!
                    }, set: { value in
                        guard value.isFinite else { return }
                        var limits = controller.loadingLimits
                        limits.maximumMemoryGB = value
                        controller.updateLoadingLimits(limits)
                    }), format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                }
                LabeledContent("Best Set Estimated Memory", value: "\(controller.selectedMemoryGB.formatted(.number.precision(.fractionLength(1)))) GB")
            } header: {
                Text("Model Loading")
            }
            .disabled(controller.isEnabled || !controller.canEnable || controller.saved.pendingChange != nil)

            Section {
                economicField("Electricity (USD/kWh)", keyPath: \.electricityPerKWh, format: .number, range: 0...100)
                economicField("Active Serving Power (Watts)", keyPath: \.servingWatts, format: .number, range: 0...10000)
                economicField("Idle Power (Watts)", keyPath: \.idlePowerInput, format: .number, range: 0...10000)
                economicField("Minimum Improvement", keyPath: \.minimumImprovement, format: .percent, range: 0.01...10)
            } header: {
                Text("Power Assumptions")
            }

            if !controller.bestModels.isEmpty {
                Section("Best Set Estimates") {
                    LabeledContent("Estimated Busy Time", value: controller.bestSetEstimate.utilization.formatted(.percent.precision(.fractionLength(0))))
                    if let requests = controller.bestSetEstimate.handledRequestsPerHour {
                        LabeledContent("Estimated Handled Requests /h", value: requests.formatted(.number.precision(.fractionLength(1))))
                    }
                    LabeledContent("Estimated Average Power", value: "\(controller.bestSetEstimate.averageWatts.formatted(.number.precision(.fractionLength(1)))) W")
                    LabeledContent("Estimated Revenue /h", value: dollars(controller.bestSetEstimate.hourlyRevenue))
                    LabeledContent("Estimated Electricity /h", value: dollars(controller.bestSetEstimate.hourlyCost))
                    LabeledContent("Estimated Net /h", value: dollars(controller.bestSetEstimate.hourlyProfit))
                }
            }

            Section {
                if controller.rankings.isEmpty {
                    Text("No comparable samples yet.").foregroundStyle(.secondary)
                }
                ForEach(controller.rankings) { rank in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(rank.id).fontWeight(.medium)
                            if controller.bestModels.contains(rank.id) {
                                Text("Recommended").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(rank.hourlyProfit, format: .currency(code: "USD").precision(.fractionLength(4))) + Text(" /h")
                        }
                        HStack {
                            Text("Estimated busy \(rank.utilization.formatted(.percent.precision(.fractionLength(0))))")
                            Spacer()
                            Text("\(rank.effectiveTPS.formatted(.number.precision(.fractionLength(1)))) output tok/s")
                            Text("· \(rank.demand) requests / \(rank.competitors) providers")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if let requests = rank.handledRequestsPerHour, let offered = rank.offeredRequestsPerHour, let seconds = rank.requestSeconds,
                           let prompt = rank.requestPromptTokens, let output = rank.requestCompletionTokens {
                            Text("≈ \(offered.formatted(.number.precision(.fractionLength(1)))) offered / \(requests.formatted(.number.precision(.fractionLength(1)))) handled requests/h · \(seconds.formatted(.number.precision(.fractionLength(1))))s per request at benchmark size (\(Int(prompt)) prompt / \(Int(output)) output tokens)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !rank.usesFleetThroughput {
                            Text("Fleet throughput unavailable — using occupancy as a rough busy-time estimate")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Model Ranking")
            }

            Section("Calibration") {
                if let date = controller.saved.calibratedAt {
                    LabeledContent("Last calibrated") { Text(date, format: .dateTime) }
                }
                LabeledContent("Unified memory", value: "\(controller.memoryGB.formatted(.number.precision(.fractionLength(0)))) GB")
                ForEach(controller.localModels) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.id).fontWeight(.medium)
                        if let exclusion = controller.eligibilityExclusions[model.id] {
                            Text(exclusion).foregroundStyle(.secondary)
                        } else if let benchmark = controller.benchmarks[model.id], benchmark.sizeBytes == model.sizeBytes {
                            Text("\(benchmark.effectiveTokensPerSecond.formatted(.number.precision(.fractionLength(1)))) effective output tok/s · \(benchmark.totalSeconds.formatted(.number.precision(.fractionLength(2))))s total · \(benchmark.decodeTokensPerSecond.formatted(.number.precision(.fractionLength(1)))) decode tok/s")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(controller.saved.failures[model.id] ?? "Not calibrated — recalibrate to include this model")
                                .foregroundStyle(.orange)
                        }
                    }
                    .font(.callout)
                }
            }

            Section("Activity") {
                if controller.events.isEmpty { Text("No decisions yet.").foregroundStyle(.secondary) }
                ForEach(controller.events) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(event.title).fontWeight(.medium)
                            Spacer()
                            Text(event.date, format: .dateTime).foregroundStyle(.secondary)
                        }
                        Text(event.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await controller.refreshDisplay() }
    }

    private func dollars(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(4)))
    }

    private var loaded: String {
        if localService.processIsRunning == false { return "None" }
        guard let state = localService.daemonState, localService.processIsRunning == true,
              abs(state.writtenAt.timeIntervalSinceNow) < 30 else { return "Waiting for a fresh daemon snapshot" }
        let models = Set(state.warmModels + state.slots.map(\.model)).sorted()
        return models.isEmpty ? "None" : models.joined(separator: ", ")
    }

    private func economicField<F: ParseableFormatStyle>(_ title: String, keyPath: WritableKeyPath<AutopilotEconomics, Double>,
                               format: F, range: ClosedRange<Double>) -> some View where F.FormatInput == Double, F.FormatOutput == String {
        LabeledContent(title) {
            TextField(title, value: Binding(get: { controller.economics[keyPath: keyPath] }, set: { value in
                guard value.isFinite else { return }
                var economics = controller.economics
                economics[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, value))
                if keyPath == \.idlePowerInput { economics.idlePowerInput = min(economics.idlePowerInput, economics.servingWatts) }
                if keyPath == \.servingWatts { economics.idlePowerInput = min(economics.idlePowerInput, economics.servingWatts) }
                controller.updateEconomics(economics)
            }), format: format)
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 100)
            .disabled(controller.isEnabled || !controller.canEnable)
        }
    }
}
#endif
