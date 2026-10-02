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
                LabeledContent("Active Model", value: active)
                LabeledContent("Best Model", value: controller.bestModel ?? "Awaiting calibration and fresh demand")
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
                LabeledContent("Consecutive Winning Samples", value: "\(controller.consecutiveSamples) / 3")
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

            Section("Earning Estimates") {
                economicField("Electricity (USD/kWh)", keyPath: \.electricityPerKWh, format: .number, range: 0...100)
                economicField("Serving Power (Watts)", keyPath: \.servingWatts, format: .number, range: 0...10000)
                economicField("Minimum Improvement", keyPath: \.minimumImprovement, format: .percent, range: 0.01...10)
            }

            Section("Model Ranking") {
                if controller.rankings.isEmpty {
                    Text("No comparable samples yet.").foregroundStyle(.secondary)
                }
                ForEach(controller.rankings) { rank in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(rank.id).fontWeight(.medium)
                            Spacer()
                            Text(rank.hourlyProfit, format: .currency(code: "USD").precision(.fractionLength(4))) + Text(" /h")
                        }
                        HStack {
                            Text("Utilization \(rank.utilization.formatted(.percent.precision(.fractionLength(0))))")
                            Spacer()
                            Text("\(rank.effectiveTPS.formatted(.number.precision(.fractionLength(1)))) output tok/s")
                            Text("· \(rank.demand) requests / \(rank.competitors) providers")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
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

    private func economicField<F: ParseableFormatStyle>(_ title: String, keyPath: WritableKeyPath<AutopilotEconomics, Double>,
                               format: F, range: ClosedRange<Double>) -> some View where F.FormatInput == Double, F.FormatOutput == String {
        LabeledContent(title) {
            TextField(title, value: Binding(get: { controller.economics[keyPath: keyPath] }, set: { value in
                guard value.isFinite else { return }
                var economics = controller.economics
                economics[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, value))
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
