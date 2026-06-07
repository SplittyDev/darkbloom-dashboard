#if os(macOS)

import SwiftUI
import FiveKit

extension OverviewTab {
    struct LocalDarkbloomSection: View {
        @Environment(APIDataController.self) private var dataController
        
        @State private var isRestarting: Bool = false
        @State private var restartingStep: String?
        @State private var restartSelection: String = "all"
        @State private var remoteRestartUser: String = ""
        @State private var remoteRestartHost: String = ""
        
        let localServiceController: LocalServiceController
        
        private let settings = Settings.shared
        private let allRestartSelection = "all"
        
        private var restartableSerialNumbers: [String] {
            settings.trackedMachineSerialNumbers
        }
        
        private var isRemoteRestartSelection: Bool {
            let nonRemoteTargets: [String] = [
                allRestartSelection,
                localServiceController.currentMachineSerialNumber
            ].compactMap(\.self)
            return !nonRemoteTargets.contains(restartSelection)
        }
        
        private func restart(serialNumber: String) async {
            restartingStep = "Determining darkbloom location..."
            let localSerialNumber = localServiceController.currentMachineSerialNumber
            if serialNumber == localSerialNumber {
                guard let darkbloomPath = try? localServiceController.fetchDarkbloomLocation() else {
                    restartingStep = "Unable to find darkbloom."
                    try? await Task.sleep(for: .seconds(5))
                    return
                }
                
                restartingStep = "Stopping darkbloom service on this Mac..."
                try? await localServiceController.stopDarkbloom(at: darkbloomPath)
                
                // Fetch network info (machine should be offline)
                if let apiKey = settings.apiKey {
                    try? await Task.sleep(for: .seconds(5))
                    try? await dataController.update(apiKey: apiKey)
                }
                
                restartingStep = "Starting darkbloom service on this Mac..."
                try? await localServiceController.startDarkbloom(at: darkbloomPath)
            } else if let target = settings.remoteRestartTargets[serialNumber] {
                restartingStep = "Restarting \(label(for: serialNumber)) over SSH..."
                do {
                    try await localServiceController.restartRemoteDarkbloom(target: target)
                } catch {
                    print(error)
                    restartingStep = "Unable to restart \(label(for: serialNumber)): \(error.localizedDescription)"
                    try? await Task.sleep(for: .seconds(5))
                    return
                }
            } else {
                restartingStep = "No restart route configured for \(serialNumber)."
                try? await Task.sleep(for: .seconds(5))
                return
            }
            
            // If there's no api key, we're done here
            guard let apiKey = settings.apiKey else {
                restartingStep = "Done."
                try? await Task.sleep(for: .seconds(5))
                return
            }
            
            restartingStep = "Waiting for provider to come back online..."
            let onlineCheckStartDate = Date.now
            while true {
                try? await Task.sleep(for: .seconds(5))
                try? await dataController.update(apiKey: apiKey)
                if dataController.machineInfo[serialNumber]?.trust.isOnline == true {
                    break
                }
                if onlineCheckStartDate.timeIntervalUntilNow > 120 {
                    restartingStep = "Timeout while waiting for provider to come back online."
                    try? await Task.sleep(for: .seconds(5))
                    return
                }
            }
            
            restartingStep = "Waiting for provider to become trusted..."
            let trustCheckStartDate = Date.now
            while true {
                try? await Task.sleep(for: .seconds(5))
                try? await dataController.update(apiKey: apiKey)
                if let machine = dataController.machineInfo[serialNumber], machine.trust.isTrusted {
                    break
                }
                if trustCheckStartDate.timeIntervalUntilNow > 120 {
                    restartingStep = "Timeout while waiting for provider to become trusted."
                    try? await Task.sleep(for: .seconds(5))
                    return
                }
            }
            
            restartingStep = "Warming up models..."
            try? await dataController.warmup(serialNumber: serialNumber)
            
            restartingStep = "Done"
            try? await Task.sleep(for: .seconds(5))
        }
        
        private func restartSelectedMachines() async {
            defer { restartingStep = nil }
            
            let serialNumbers: [String]
            if restartSelection == allRestartSelection {
                serialNumbers = restartableSerialNumbers
            } else {
                serialNumbers = [restartSelection]
            }
            
            guard !serialNumbers.isEmpty else {
                restartingStep = "No machines selected."
                try? await Task.sleep(for: .seconds(5))
                return
            }
            
            for serialNumber in serialNumbers {
                restartingStep = "Preparing \(label(for: serialNumber))..."
                await restart(serialNumber: serialNumber)
            }
        }
        
        private func label(for serialNumber: String) -> String {
            if serialNumber == localServiceController.currentMachineSerialNumber {
                return "This Mac (\(serialNumber))"
            }
            if let displayName = dataController.machineInfo[serialNumber]?.hardware.modelDisplayName {
                return "\(displayName) (\(serialNumber))"
            }
            return serialNumber
        }
        
        private func loadRemoteRestartFields(serialNumber: String) {
            guard serialNumber != allRestartSelection else {
                remoteRestartUser = ""
                remoteRestartHost = ""
                return
            }
            let target = settings.remoteRestartTargets[serialNumber]
            remoteRestartUser = target?.user ?? ""
            remoteRestartHost = target?.host ?? ""
        }
        
        private func saveRemoteRestartTarget() {
            let trimmedUser = remoteRestartUser.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedHost = remoteRestartHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isRemoteRestartSelection, !trimmedUser.isEmpty, !trimmedHost.isEmpty else { return }
            settings.setRemoteRestartTarget(
                MachineRestartTarget(
                    serialNumber: restartSelection,
                    user: trimmedUser,
                    host: trimmedHost
                )
            )
        }
        
        var body: some View {
            Section {
                LabeledContent {
                    if let isRunning = localServiceController.processIsRunning {
                        Text(isRunning ? "Running" : "Stopped")
                    } else {
                        ProgressView().controlSize(.small)
                    }
                } label: {
                    Text("Process Status")
                }
                .animation(.interactiveSpring, value: localServiceController.processIsRunning)
                
                Picker("Restart Target", selection: $restartSelection) {
                    Text("All tracked machines").tag(allRestartSelection)
                    Divider()
                    ForEach(restartableSerialNumbers, id: \.self) { serialNumber in
                        Text(label(for: serialNumber)).tag(serialNumber)
                    }
                }
                
                if isRemoteRestartSelection {
                    LabeledContent {
                        TextField("macOS account name", text: $remoteRestartUser)
                            .textFieldStyle(.roundedBorder)
                    } label: {
                        Text("SSH User")
                    }
                    
                    LabeledContent {
                        TextField("Tailscale host or IP", text: $remoteRestartHost)
                            .textFieldStyle(.roundedBorder)
                    } label: {
                        Text("SSH Host")
                    }
                    
                    HStack {
                        Spacer()
                        Button("Save SSH Target") {
                            saveRemoteRestartTarget()
                        }
                        .disabled(
                            remoteRestartUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            remoteRestartHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
                
                if let restartingStep {
                    LabeledContent {
                        Text(restartingStep)
                    } label: {
                        Text("Restart Status")
                    }
                    .transition(.opacity)
                }
            } header: {
                HStack(alignment: .bottom) {
                    Label("Darkbloom Process", systemImage: "apple.terminal")
                    Spacer()
                    Button {
                        isRestarting = true
                        Task {
                            await restartSelectedMachines()
                            isRestarting = false
                        }
                    } label: {
                        Text("Restart")
                    }
                    .disabled(isRestarting)
                }
            }
            .animation(.interactiveSpring, value: restartingStep)
            .onAppear {
                loadRemoteRestartFields(serialNumber: restartSelection)
            }
            .onChange(of: restartSelection) { _, serialNumber in
                loadRemoteRestartFields(serialNumber: serialNumber)
            }
        }
    }
}

#endif
