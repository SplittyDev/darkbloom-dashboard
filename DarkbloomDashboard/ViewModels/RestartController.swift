import Foundation
import FiveKit
import Citadel
import NIOCore
import NIOFoundationEssentialsCompat

@Observable
final class RestartTask {
    let machine: MachineModel
    var task: Task<Void, Never>?
    var subtaskLog: [RestartSubtask] = []
    var status: RestartStatus = .inProgress
    
    init(machine: MachineModel) {
        self.machine = machine
    }
    
    func subtask(message: String) -> RestartSubtask {
        let subtask = RestartSubtask(message: message)
        subtaskLog.append(subtask)
        return subtask
    }
    
    func withSubtask<T>(_ message: String, _ action: (RestartSubtask) async throws -> T) async rethrows -> T {
        let subtask = self.subtask(message: message)
        do {
            let result = try await action(subtask)
            subtask.complete(with: .success)
            return result
        } catch {
            print("Error in restart subtask: \(error)")
            subtask.complete(with: .error(error))
            throw error
        }
    }
    
    func complete(with status: RestartStatus) {
        self.status = status
    }
}

private nonisolated final class SSHClientBox: @unchecked Sendable {
    let client: SSHClient

    init(_ client: SSHClient) {
        self.client = client
    }
}

private actor SSHClientHolder {
    let box: SSHClientBox
    
    init(connectionInfo: SSHConnectionInfo) async throws {
        let clientSettings = connectionInfo.sshClientSettings
        self.box = SSHClientBox(try await SSHClient.connect(to: clientSettings))
    }
    
    func executeCommand(_ command: String, mergeStreams: Bool = false) async throws -> ByteBuffer {
        try await box.client.executeCommand(command, mergeStreams: mergeStreams)
    }
    
    func disconnect() async throws {
        try await box.client.close()
    }
}

@Observable
final class RestartSubtask: Identifiable, Equatable {
    let id: UUID = UUID()
    let startDate: Date
    var endDate: Date?
    let message: String
    var status: RestartStatus
    var additionalLogs: [String] = []
    
    init(message: String, status: RestartStatus = .inProgress) {
        self.startDate = Date.now
        self.message = message
        self.status = status
    }
    
    func log(error: any Error) {
        additionalLogs.append(String(describing: error))
    }
    
    func log(_ message: String) {
        additionalLogs.append(message)
    }
    
    func complete(with status: RestartStatus) {
        self.endDate = Date.now
        self.status = status
    }
    
    static func ==(lhs: RestartSubtask, rhs: RestartSubtask) -> Bool {
        lhs.id == rhs.id
    }
}

enum RestartStatus: Equatable {
    case inProgress
    case success
    case error(any Error)
    
    var wasSuccessful: Bool {
        if case .success = self {
            true
        } else {
            false
        }
    }
    
    var inProgress: Bool {
        if case .inProgress = self {
            true
        } else {
            false
        }
    }
    
    static func ==(lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
            case (.inProgress, .inProgress): true
            case (.success, .success): true
            case (.error, .error): true
            default: false
        }
    }
}

enum RestartError: Error {
    case darkbloomNotFound
    case failedToStopLocalService
    case failedToStartLocalService
    case apiKeyMissing
    case onlineCheckTimeout
    case trustCheckTimeout
    case missingRemoteConnectionInfo
    case failedToRestartRemoteService
    case failedToEstablishSSHConnection
    case unsupportedOnCurrentOS
}

@Observable
final class RestartController {
    static let shared = RestartController()
    
    private let dataController = APIDataController.shared
    
    #if os(macOS)
    private let localServiceController = LocalServiceController.shared
    #endif
    
    private(set) var tasks: [String: RestartTask] = [:]
    private(set) var history: [RestartTask] = []
    
    private init() {
    }
    
    func restart(machine: MachineModel) -> RestartTask {
        if let existingTask = tasks[machine.serialNo] {
            return existingTask
        }
        
        let task = RestartTask(machine: machine)
        tasks[machine.serialNo] = task
        task.task = Task {
            
            // Stop automatic data updates
            dataController.stopAllUpdates()
            
            // Clear machine info for clean status checking
            dataController.clearMachineInfo(for: task.machine.serialNo)
            
            // Perform restart
            do {
                try await self.performRestart(for: task)
                task.complete(with: .success)
            } catch {
                task.complete(with: .error(error))
            }
            
            // Resume automatic data updates
            await dataController.update()
            
            // Remove task from active tracking
            tasks.removeValue(forKey: task.machine.serialNo)
            
            // Append task to restart history
            history.append(task)
        }
        
        return task
    }
    
    func cancel(for serial: String) {
        guard let data = tasks[serial] else { return }
        data.task?.cancel()
    }
    
    private func performRestart(for task: RestartTask) async throws {
        
        #if os(macOS)
        let isLocalProvider = await task.withSubtask("Checking target provider") { t in
            if let localSerialNumber = localServiceController.currentMachineSerialNumber {
                if task.machine.serialNo == localSerialNumber {
                    t.log("Target is local provider")
                    return true
                }
            }
            t.log("Target is remote provider")
            return false
        }
        #endif
        
        try Task.checkCancellation()
        
        #if os(macOS)
        if isLocalProvider {
            try await performLocalRestart(for: task)
        } else {
            try await performRemoteRestart(for: task)
        }
        #else
        try await performRemoteRestart(for: task)
        #endif
        
        try Task.checkCancellation()
        
        guard Settings.shared.apiKey != nil else {
            throw RestartError.apiKeyMissing
        }
        
        var machineInfo = try await task.withSubtask("Waiting for provider to come back online") { t in
            var lastCheckDate = Date.now
            while true {
                try? await dataController.refreshStatsAndAttestations()
                
                if let info = task.machine.currentInfo {
                    if info.trust.isTrusted {
                        t.log("Provider is back online and trusted")
                        return info
                    } else if info.trust.isOnline {
                        t.log("Provider is back online")
                        return info
                    }
                }
                
                if lastCheckDate.timeIntervalUntilNow > 120 {
                    t.log("Online check timed out after 120s")
                    throw RestartError.onlineCheckTimeout
                }
                
                lastCheckDate = Date.now
                try await Task.sleep(for: .seconds(5))
            }
        }
        
        if !machineInfo.trust.isTrusted {
            try Task.checkCancellation()
            try await task.withSubtask("Waiting for provider to become trusted") { t in
                var lastCheckDate = Date.now
                while true {
                    try? await dataController.refreshStatsAndAttestations()
                    
                    if let info = task.machine.currentInfo {
                        if info.trust.isTrusted {
                            t.log("Provider is trusted")
                            machineInfo = info
                            return
                        }
                    }
                    
                    if lastCheckDate.timeIntervalUntilNow > 120 {
                        t.log("Trust check timed out after 120s")
                        throw RestartError.trustCheckTimeout
                    }
                    
                    lastCheckDate = Date.now
                    try await Task.sleep(for: .seconds(5))
                }
            }
        }
        
        for model in machineInfo.activity.models {
            try Task.checkCancellation()
            try? await task.withSubtask("Warming up '\(model.id)'") { t in
                try await dataController.warmup(model: model, for: task.machine.serialNo)
            }
        }
    }
    
    #if os(macOS)
    private func performLocalRestart(for task: RestartTask) async throws {
        let darkbloomLocation: String? = try? await task.withSubtask("Finding darkbloom location") { t in
            let location = try localServiceController.fetchDarkbloomLocation()
            t.log("Found darkbloom at \(location)")
            return location
        }
        
        guard let darkbloomLocation else {
            throw RestartError.darkbloomNotFound
        }
        
        try await task.withSubtask("Stopping local darkbloom service") { t in
            do {
                try await localServiceController.stopDarkbloom(at: darkbloomLocation)
            } catch {
                t.log(error: error)
                throw RestartError.failedToStopLocalService
            }
        }
        
        try await task.withSubtask("Starting local darkbloom service") { t in
            do {
                try await localServiceController.startDarkbloom(at: darkbloomLocation)
            } catch {
                t.log(error: error)
                throw RestartError.failedToStartLocalService
            }
        }
    }
    #endif
    
    private func performRemoteRestart(for task: RestartTask) async throws {
        let connectionInfo: SSHConnectionInfo = try await task
            .withSubtask("Looking up SSH connection info") { t in
                guard let connectionInfo = task.machine.sshConnectionInfo else {
                    throw RestartError.missingRemoteConnectionInfo
                }
                return connectionInfo
            }
        
        let ssh: SSHClientHolder = try await task.withSubtask("Establishing SSH connection") { t in
            do {
                return try await SSHClientHolder(connectionInfo: connectionInfo)
            } catch {
                t.log(error: error)
                throw RestartError.failedToEstablishSSHConnection
            }
        }
        
        await task.withSubtask("Stopping darkbloom service") { t in
            let stopResp = try? await ssh.executeCommand("~/.darkbloom/bin/darkbloom stop")
            if var stopResp, let output = stopResp.readString(length: stopResp.readableBytes, encoding: .utf8) {
                t.log(output)
            }
        }
        
        try await task.withSubtask("Starting darkbloom service") { t in
            do {
                var startResp = try await ssh.executeCommand("~/.darkbloom/bin/darkbloom start --all", mergeStreams: true)
                if let output = startResp.readString(length: startResp.readableBytes, encoding: .utf8) {
                    t.log(output)
                }
            } catch {
                t.log(error: error)
                throw RestartError.failedToRestartRemoteService
            }
        }
    }
}
