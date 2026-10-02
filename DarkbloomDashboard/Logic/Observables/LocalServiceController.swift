#if os(macOS)

import Foundation
import IOKit

struct DarkbloomDaemonState: Decodable, Sendable {
    struct ModelSwitch: Decodable, Sendable {
        let outcome: String
        let models: [String]
        var remaining: Int? = nil
    }

    struct Lifecycle: Decodable, Sendable {
        let outcome: String
        var remaining: Int? = nil
    }

    struct Capacity: Decodable, Sendable {
        let gpuMemoryActiveGb: Double
        let gpuMemoryCacheGb: Double
        let totalMemoryGb: Double
    }
    
    struct Trust: Decodable, Sendable {
        let status: String
        let receivedAt: Date
        let reason: String
        let trustLevel: String
    }
    
    struct Slot: Decodable, Sendable {
        let kvBackendRequested: String
        let mtpEnabled: Bool
        let kvBackend: String
        let mtpActive: Bool
        let model: String
    }
    
    struct ProcessIdentity: Decodable, Sendable {
        let pid: Int
        let startTimeMicros: Int64
    }
    
    struct Stats: Decodable, Sendable {
        let usageGaps: Int
        let tokensGenerated: Int
        let requestsServed: Int
    }
    
    let writtenAt: Date
    let capacity: Capacity
    let schema: Int
    let currentModel: String
    let trust: Trust
    let pid: Int
    let version: String
    let slots: [Slot]
    let warmModels: [String]
    let startedAt: Date
    let processIdentity: ProcessIdentity
    let stats: Stats
    let inferenceActive: Bool
    let attestationPublicKey: String?
    var advertisedModels: [String]? = nil
    var modelSwitch: ModelSwitch? = nil
    var lifecycle: Lifecycle? = nil

    // Hosting selection changes before lazy-loaded slots/currentModel do.
    var selectedModels: [String] {
        Array(Set(advertisedModels ?? (slots.map(\.model) + [currentModel])).subtracting([""])).sorted()
    }

    var selectionIsSettled: Bool {
        lifecycle?.outcome == "serving" &&
            (modelSwitch == nil || ["serving", "switched", "failed", "busy"].contains(modelSwitch!.outcome))
    }
    
    static func decode(from data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(Self.self, from: data)
    }
}

extension DarkbloomDaemonState {
    private enum CodingKeys: String, CodingKey {
        case writtenAt, capacity, schema, currentModel, trust, pid, version, slots, warmModels
        case startedAt, processIdentity, stats, inferenceActive, attestationPublicKey
        case advertisedModels, modelSwitch, lifecycle
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        writtenAt = try values.decode(Date.self, forKey: .writtenAt)
        capacity = try values.decode(Capacity.self, forKey: .capacity)
        schema = try values.decode(Int.self, forKey: .schema)
        // A valid serving selection can have no loaded model yet (lazy loading).
        currentModel = try values.decodeIfPresent(String.self, forKey: .currentModel) ?? ""
        slots = try values.decodeIfPresent([Slot].self, forKey: .slots) ?? []
        trust = try values.decode(Trust.self, forKey: .trust)
        pid = try values.decode(Int.self, forKey: .pid)
        version = try values.decode(String.self, forKey: .version)
        warmModels = try values.decode([String].self, forKey: .warmModels)
        startedAt = try values.decode(Date.self, forKey: .startedAt)
        processIdentity = try values.decode(ProcessIdentity.self, forKey: .processIdentity)
        stats = try values.decode(Stats.self, forKey: .stats)
        inferenceActive = try values.decode(Bool.self, forKey: .inferenceActive)
        attestationPublicKey = try values.decodeIfPresent(String.self, forKey: .attestationPublicKey)
        advertisedModels = try values.decodeIfPresent([String].self, forKey: .advertisedModels)
        modelSwitch = try values.decodeIfPresent(ModelSwitch.self, forKey: .modelSwitch)
        lifecycle = try values.decodeIfPresent(Lifecycle.self, forKey: .lifecycle)
    }
}

@MainActor @Observable
final class LocalServiceController {
    static let shared = LocalServiceController()
    
    private var launchctlTask: Task<Void, Never>?
    
    private(set) var processExists: Bool = false
    private(set) var processIsRunning: Bool?
    
    private(set) var currentMachineSerialNumber: String?
    private(set) var daemonState: DarkbloomDaemonState?
    
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
                self.daemonState = try? await self.fetchDaemonState()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
    
    func refreshSnapshot() async {
        if let status = try? await fetchStatus() {
            processExists = status.exists
            processIsRunning = status.running
        } else {
            processIsRunning = nil
        }
        daemonState = try? await fetchDaemonState()
    }

    func stopObservation() {
        launchctlTask?.cancel()
        
        launchctlTask = nil
    }
    
    private func getSerialNumber() -> String? {
        let platformExpert = unsafe IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard platformExpert != 0 else { return nil }
        defer {
            IOObjectRelease(platformExpert)
        }
        guard let serial = unsafe IORegistryEntryCreateCFProperty(
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
        let re = /(?P<pid>\d+|-)\s+(?P<status>-?\d+)\s+(?P<service>[\w.]+)/
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
    
    @concurrent private func fetchDaemonState() async throws -> DarkbloomDaemonState {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".darkbloom/daemon-state.json")
        return try DarkbloomDaemonState.decode(from: Data(contentsOf: url))
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
