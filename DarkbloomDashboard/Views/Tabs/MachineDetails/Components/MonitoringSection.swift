import SwiftUI
import FiveKit

extension MachineDetailTab {
    
    @Observable
    final class MonitoringViewModel {
        private let restartController = RestartController.shared
        
        var restartTask: RestartTask?
        
        init() {
        }
        
        func restartProvider(machine: MachineModel) {
            // Cancel existing task
            if let restartTask, restartTask.status.inProgress {
                restartController.cancel(for: machine.serialNo)
                self.restartTask = nil
            }
            
            // Spawn new restart task
            restartTask = restartController.restart(machine: machine)
        }
    }
    
    struct MonitoringSection: View {
        @State private var viewModel = MonitoringViewModel()
        
        private let settings = Settings.shared
        private let machine: MachineModel
        
        init(machine: MachineModel) {
            self.machine = machine
        }
        
        #if os(macOS)
        private var isLocalMachine: Bool {
            machine.serialNo == LocalServiceController.shared.currentMachineSerialNumber
        }
        #endif
        
        var body: some View {
            Group {
                #if os(macOS)
                if isLocalMachine {
                    LocalMonitoringSection()
                } else {
                    RemoteMonitoringSection()
                }
                #else
                RemoteMonitoringSection()
                #endif
            }
            .environment(viewModel)
            .environment(machine)
        }
    }
    
    private struct RestartStatusView: View {
        let restartTask: RestartTask
        
        var body: some View {
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
    
    #if os(macOS)
    private struct LocalMonitoringSection: View {
        @Environment(LocalServiceController.self) private var localServiceController
        @Environment(MonitoringViewModel.self) private var viewModel
        @Environment(MachineModel.self) private var machine
        
        var body: some View {
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
                
                if let restartTask = viewModel.restartTask {
                    RestartStatusView(restartTask: restartTask)
                }
            } header: {
                Text("Local Service")
            } footer: {
                HStack {
                    Spacer()
                    Button {
                        viewModel.restartProvider(machine: machine)
                    } label: {
                        Text("Restart")
                    }
                    .controlSize(.small)
                }
            }
        }
    }
    #endif
    
    private struct RemoteMonitoringSection: View {
        @Environment(MonitoringViewModel.self) private var viewModel
        @Environment(MachineModel.self) private var machine
        
        @State private var showRemoteAccessConfigurator: Bool = false
        
        var body: some View {
            Section {
                if let restartTask = viewModel.restartTask {
                    RestartStatusView(restartTask: restartTask)
                }
            } header: {
                Text("Remote Connection")
            } footer: {
                HStack(alignment: .top) {
                    Text("We recommend using Tailscale to easily establish a secure remote connection.")
                    Spacer()
                    
                    Button {
                        showRemoteAccessConfigurator = true
                    } label: {
                        Text("Configure Remote Access")
                    }
                    .controlSize(.small)
                    
                    if machine.sshConnectionInfo != nil {
                        Button {
                            viewModel.restartProvider(machine: machine)
                        } label: {
                            Text("Restart")
                        }
                        .controlSize(.small)
                    }
                }
            }
            .sheet(isPresented: $showRemoteAccessConfigurator) {
                SSHConfigurationSheet(machine: machine)
            }
        }
    }
}
