import SwiftUI
import FiveKit

struct MachineDetailTab: View {
    @State private var lastMachineInfo: MachineInfo?
    
    private let dataController = APIDataController.shared
    
    let serialNo: String
    
    var body: some View {
        Form {
            if let machine = dataController.machineInfo[serialNo] ?? lastMachineInfo {
                Section {
                    LabeledContent {
                        Text(machine.providerId)
                    } label: {
                        Text("Provider ID")
                    }
                }
                #if os(macOS)
                MonitoringSection(machineInfo: machine)
                #endif
                HardwareSection(hardware: machine.hardware)
                #if os(macOS)
                TrustSection(trust: machine.trust, showAll: true)
                #else
                TrustSection(trust: machine.trust, showAll: false)
                #endif
                NetworkSection(serialNo: serialNo, activity: machine.activity)
            }
        }
        .formStyle(.grouped)
        .onChange(of: dataController.machineInfo, initial: true) {
            if let machineInfo = dataController.machineInfo[serialNo] {
                lastMachineInfo = machineInfo
            }
        }
    }
}

struct VerbatimStringParseStrategy: ParseStrategy {
    typealias ParseInput = String
    typealias ParseOutput = String
    
    func parse(_ value: String) throws -> String {
        value
    }
}

struct CleanStringFormatStyle: ParseableFormatStyle {
    typealias Strategy = VerbatimStringParseStrategy
    typealias FormatInput = String
    typealias FormatOutput = String
    
    var parseStrategy: VerbatimStringParseStrategy {
        VerbatimStringParseStrategy()
    }
    
    func format(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ParseableFormatStyle where Self == CleanStringFormatStyle {

    static var cleanString: CleanStringFormatStyle {
        CleanStringFormatStyle()
    }
}

extension MachineDetailTab {
    
    #if os(macOS)
    struct MonitoringSection: View {
        @Environment(LocalServiceController.self) private var localServiceController
        @Environment(RestartController.self) private var restartController
        
        @State private var restartTask: RestartTask?
        @State private var remoteTarget: MachineRestartTarget
        
        private let settings = Settings.shared
        private let machineInfo: MachineInfo
        
        init(machineInfo: MachineInfo) {
            self.machineInfo = machineInfo
            if let remoteTarget = settings.remoteRestartTargets[machineInfo.serialNumber] {
                self.remoteTarget = remoteTarget
            } else {
                self.remoteTarget = MachineRestartTarget(
                    serialNumber: machineInfo.serialNumber,
                    user: "",
                    host: ""
                )
            }
        }
        
        private var isLocalMachine: Bool {
            machineInfo.serialNumber == localServiceController.currentMachineSerialNumber
        }
        
        private func restartProvider() {
            
            // Cancel existing task
            if let restartTask, restartTask.status.inProgress {
                restartController.cancel(for: machineInfo.serialNumber)
                self.restartTask = nil
            }
            
            // Spawn new restart task
            restartTask = restartController.restart(serial: machineInfo.serialNumber)
        }
        
        @ViewBuilder private var restartStatusView: some View {
            if let restartTask {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Restart Status")
                        Spacer()
                        switch restartTask.status {
                            case .inProgress:
                                EmptyView()
                            case .success:
                                Text(Image(systemName: "checkmark.circle"))
                                    .foregroundStyle(.secondary)
                            case .error:
                                Text(Image(systemName: "xmark.circle"))
                                    .foregroundStyle(.red)
                        }
                    }
                    
                    if !restartTask.status.wasSuccessful {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(restartTask.subtaskLog) { subtask in
                                VStack(alignment: .leading) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(subtask.message)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                        switch subtask.status {
                                            case .inProgress:
                                                ProgressView()
                                                    .controlSize(.small)
                                            case .success:
                                                Text(Image(systemName: "checkmark"))
                                                    .foregroundStyle(.secondary)
                                            case .error:
                                                Text(Image(systemName: "xmark"))
                                                    .foregroundStyle(.red)
                                        }
                                    }
                                    
                                    if let additionalLogs = subtask.additionalLogs.nilIfEmpty {
                                        VStack(alignment: .leading) {
                                            ForEach(additionalLogs, id: \.self) { log in
                                                Text(log)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        .padding(.leading, 8)
                                        .font(.caption)
                                        .transition(.opacity)
                                    }
                                }
                                .animation(.interactiveSpring, value: subtask.additionalLogs)
                            }
                        }
                        .font(.footnote)
                        .padding()
                        .background(Color.quaternarySystemFill)
                        .clipShape(.rect(cornerRadius: 12))
                        .animation(.interactiveSpring, value: restartTask.subtaskLog)
                        .transition(.opacity)
                    }
                } // VStack
                .animation(.smooth, value: restartTask.status)
            }
        }
        
        var body: some View {
            if isLocalMachine {
                Section {
                    LabeledContent {
                        if localServiceController.processIsRunning == true {
                            Text("Running")
                        } else {
                            Text("Stopped")
                        }
                    } label: {
                        Text("Service Status")
                    }
                    
                    restartStatusView
                } header: {
                    Text("Local Service")
                } footer: {
                    HStack {
                        Spacer()
                        Button {
                            restartProvider()
                        } label: {
                            Text("Restart")
                        }
                        .controlSize(.small)
                    }
                }
            } else {
                Section {
                    LabeledContent {
                        TextField("", value: $remoteTarget.user, format: .cleanString, prompt: Text("MacOS Account Name"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    } label: {
                        Text("SSH User")
                    }
                    
                    LabeledContent {
                        TextField("", value: $remoteTarget.host, format: .cleanString, prompt: Text("Host / IP Address"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    } label: {
                        Text("SSH Host")
                    }
                    
                    restartStatusView
                } header: {
                    Text("Remote Connection")
                } footer: {
                    HStack(alignment: .top) {
                        Text("We recommend using Tailscale to easily establish a secure remote connection.")
                        Spacer()
                        Button {
                            restartProvider()
                        } label: {
                            Text("Restart")
                        }
                        .controlSize(.small)
                    }
                }
                .onChange(of: remoteTarget) {
                    guard !remoteTarget.user.isEmpty && !remoteTarget.host.isEmpty else { return }
                    settings.setRemoteRestartTarget(remoteTarget)
                }
            }
        }
    }
    #endif
    
    struct HardwareSection: View {
        let hardware: MachineHardwareInfo
        
        var body: some View {
            Section {
                LabeledContent {
                    Text(hardware.modelDisplayName)
                } label: {
                    Text("Model")
                }
                LabeledContent {
                    Text("\(hardware.memoryGb) GB")
                } label: {
                    Text("Unified Memory")
                }
                LabeledContent {
                    Text("\(hardware.memoryBandwidthGbs) GB/s")
                } label: {
                    Text("Memory Bandwidth")
                }
            } header: {
                Text("Hardware")
            }
        }
    }
    
    struct TrustSection: View {
        let trust: MachineTrustInfo
        let showAll: Bool
        
        var body: some View {
            Section {
                LabeledContent {
                    Text(trust.trustLevel.displayName)
                } label: {
                    Text("Trust Level")
                }
                if showAll || !trust.mdaVerified {
                    LabeledContent {
                        Text(trust.mdaVerified ? "Yes" : "No")
                    } label: {
                        Text("Mobile Device Attestation (MDA)")
                    }
                }
                if showAll || !trust.mdmVerified {
                    LabeledContent {
                        Text(trust.mdmVerified ? "Yes" : "No")
                    } label: {
                        Text("Mobile Device Management (MDM)")
                    }
                }
                if showAll || !trust.authenticatedRootEnabled {
                    LabeledContent {
                        Text(trust.authenticatedRootEnabled ? "Yes" : "No")
                    } label: {
                        Text("Authenticated Root")
                    }
                }
                if showAll || !trust.sipEnabled {
                    LabeledContent {
                        Text(trust.sipEnabled ? "Yes" : "No")
                    } label: {
                        Text("System Integrity Protection")
                    }
                }
                if showAll || !trust.secureBootEnabled {
                    LabeledContent {
                        Text(trust.secureBootEnabled ? "Yes" : "No")
                    } label: {
                        Text("Secure Boot")
                    }
                }
                if showAll || !trust.secureEnclave {
                    LabeledContent {
                        Text(trust.secureEnclave ? "Yes" : "No")
                    } label: {
                        Text("Secure Enclave")
                    }
                }
            } header: {
                HStack {
                    Text("Trust & Attestation")
                    Spacer()
                    TrustExplanationButton(trust: trust)
                }
            }
            .animation(.snappy, value: trust)
        }
    }
    
    struct NetworkSection: View {
        @Environment(APIDataController.self) private var dataController
        @State private var warmupInProgress: Bool = false
        
        let serialNo: String
        let activity: MachineActivityInfo
        
        var body: some View {
            Section {
                LabeledContent {
                    HStack(alignment: .bottom) {
                        ForEach(activity.models) { model in
                            Pill {
                                Text(model.displayName)
                            }
                            .controlSize(.small)
                        }
                    }
                } label: {
                    Text("Models")
                }
                LabeledContent {
                    Text(activity.requestsServed, format: .number)
                        .contentTransition(.numericText())
                } label: {
                    Text("Requests Served")
                }
                LabeledContent {
                    Text(activity.tokensGenerated, format: .number)
                        .contentTransition(.numericText())
                } label: {
                    Text("Tokens Generated")
                }
            } header: {
                Text("Network")
            } footer: {
                HStack {
                    Spacer()
                    Button {
                        warmupInProgress = true
                        Task {
                            try? await dataController.warmup(serialNumber: serialNo)
                            warmupInProgress = false
                        }
                    } label: {
                        Text("Warmup")
                    }
                    .disabled(warmupInProgress)
                }
            }
            .animation(.snappy, value: activity)
        }
    }
}

#Preview(traits: .controllers) {
    MachineDetailTab(serialNo: "NJD6MGW279")
}
