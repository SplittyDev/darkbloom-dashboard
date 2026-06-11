#if os(macOS)

import Foundation
import IOKit

struct MachineRestartTarget: Codable, Equatable, Identifiable {
    var id: String { serialNumber }

    let serialNumber: String
    var user: String
    var host: String

    var sshRestartArguments: [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=10",
            "-o", "StrictHostKeyChecking=accept-new",
            "\(user)@\(host)",
            "~/.darkbloom/bin/darkbloom stop; sleep 2; ~/.darkbloom/bin/darkbloom start --all"
        ]
    }
}

@MainActor @Observable
final class LocalServiceController {
    static let shared = LocalServiceController()
    
    private var launchctlTask: Task<Void, Never>?
    
    private(set) var processExists: Bool = false
    private(set) var processIsRunning: Bool?
    
    private(set) var currentMachineSerialNumber: String?
    
    private init() {
    }
    
    func setup() {
        currentMachineSerialNumber = getSerialNumber()
    }
    
    func startObservation() {
        launchctlTask?.cancel()
        launchctlTask = Task {
            while !Task.isCancelled {
                if let (exists, running) = try? await self.fetchStatus() {
                    self.processExists = exists
                    self.processIsRunning = running
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    
    func stopObservation() {
        launchctlTask?.cancel()
        launchctlTask = nil
    }
    
    private func getSerialNumber() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return nil }
        defer {
            IOObjectRelease(platformExpert)
        }
        guard let serial = IORegistryEntryCreateCFProperty(
            platformExpert,
            "IOPlatformSerialNumber" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }
        return serial
    }
    
    private func fetchStatus() async throws -> (exists: Bool, running: Bool)? {
        guard let launchctlOutput = try? await run("/bin/launchctl", ["list"]) else { return nil }
        let re = /(?P<pid>\d+|-)\s+(?P<status>\d+)\s+(?P<service>[\w.]+)/
        for line in launchctlOutput.split(separator: "\n") {
            guard let result = try? re.firstMatch(in: line) else { continue }
            guard result.output.service == "io.darkbloom.provider" else { continue }
            return (exists: true, running: result.output.pid != "-")
        }
        return (exists: false, running: false)
    }
    
    func darkbloomExists() -> Bool {
        do {
            _ = try fetchDarkbloomLocation()
            return true
        } catch {
            return false
        }
    }
    
    func fetchDarkbloomLocation() throws -> String {
        let path = FileManager.default
                .homeDirectoryForCurrentUser
                .appendingPathComponent(".darkbloom/bin/darkbloom")
                .path(percentEncoded: false)
        if FileManager.default.fileExists(atPath: path) {
            return path
        } else {
            throw CocoaError(.fileNoSuchFile)
        }
    }
    
    func stopDarkbloom(at path: String) async throws {
        print("Stopping darkbloom...")
        let stopOutput = try await run(path, ["stop"])
        print("-> \(stopOutput)")
    }
    
    func startDarkbloom(at path: String) async throws {
        print("Starting darkbloom...")
        let startOutput = try await run(path, ["start", "--all"])
        print("-> \(startOutput)")
    }

    func restartRemoteDarkbloom(machine: MachineModel, connectionInfo: SSHConnectionInfo) async throws {
        print("Restarting darkbloom on remote target: \(connectionInfo.user)@\(connectionInfo.host) (\(machine.serialNo))...")
        let restartOutput = try await run("/usr/bin/ssh", connectionInfo.sshRestartArguments)
        print("-> \(restartOutput)")
    }
    
    @concurrent private func run(_ executable: String, _ arguments: [String]) async throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let error = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            print("run: Error. Status: \(process.terminationStatus) Message: \(error)")
            throw NSError(
                domain: "LaunchctlError",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: error.isEmpty ? output : error
                ]
            )
        }

        return output
    }
}

#endif
