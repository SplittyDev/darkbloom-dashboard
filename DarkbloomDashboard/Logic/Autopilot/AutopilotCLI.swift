#if os(macOS)
import Foundation
import Darwin

/// Child output goes to files, so a verbose benchmark cannot fill a pipe and deadlock.
/// Stop/switch are allowed to finish their graceful drain even when Autopilot is paused.
enum AutopilotCLI {
    @concurrent static func run(executable: String, arguments: [String], timeout: TimeInterval = 900) async throws -> String {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdout = directory.appendingPathComponent("stdout")
        let stderr = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdout.path, contents: nil)
        FileManager.default.createFile(atPath: stderr.path, contents: nil)
        let output = try FileHandle(forWritingTo: stdout)
        let errors = try FileHandle(forWritingTo: stderr)
        defer { try? output.close(); try? errors.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        var effectiveArguments = arguments
        if arguments.first == "benchmark" {
            // The CLI also applies enabled_models to an explicit benchmark --model.
            // Use a private temporary copy with just that selection filter cleared.
            let config = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/darkbloom/provider.toml")
            let original = FileManager.default.fileExists(atPath: config.path)
                ? try String(contentsOf: config, encoding: .utf8) : ""
            let copy = directory.appendingPathComponent("benchmark.toml")
            try benchmarkConfiguration(original).write(to: copy, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
            effectiveArguments += ["--config", copy.path]
        }
        process.arguments = effectiveArguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let deadline = Date.now.addingTimeInterval(timeout)
        // This polling runs off the main actor and deliberately does not cancel a drain command.
        while process.isRunning && Date.now < deadline {
            // An independent sleep retains the timeout even if the caller is cancelled.
            await Task.detached { try? await Task.sleep(for: .milliseconds(200)) }.value
        }
        if process.isRunning {
            process.terminate()
            // Give the child time to release its model before another action can be attempted.
            let terminationDeadline = Date.now.addingTimeInterval(5)
            while process.isRunning && Date.now < terminationDeadline {
                await Task.detached { try? await Task.sleep(for: .milliseconds(100)) }.value
            }
            if process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                let killDeadline = Date.now.addingTimeInterval(5)
                while process.isRunning && Date.now < killDeadline {
                    await Task.detached { try? await Task.sleep(for: .milliseconds(100)) }.value
                }
            }
            throw AutopilotError.message("darkbloom \(arguments.first ?? "command") timed out. Check Local Service before resuming; a drain may still be pending.")
        }
        // isRunning is already false, so terminationStatus is available. Do not call
        // waitUntilExit(): its run-loop wait can hang after an async thread hop,
        // even when the child has exited, bypassing the deadline above.
        let result = try String(contentsOf: stdout, encoding: .utf8)
        guard process.terminationStatus == 0 else {
            let detail = (try? String(contentsOf: stderr, encoding: .utf8)) ?? ""
            throw AutopilotError.message("darkbloom \(arguments.first ?? "command") failed (\(process.terminationStatus)): \((detail.isEmpty ? result : detail).suffix(2000))")
        }
        return result
    }

    static func benchmarkConfiguration(_ original: String) throws -> String {
        // Match only the backend section. The array scanner honors quotes and comments,
        // so multiline arrays and # or ] inside a model identifier remain well-defined.
        let sectionPattern = try NSRegularExpression(pattern: #"(?m)^\[backend\][ \t]*(?:#.*)?$"#)
        guard let section = sectionPattern.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)),
              let sectionRange = Range(section.range, in: original) else {
            return original + "\n[backend]\nenabled_models = []\n"
        }
        let remainder = String(original[sectionRange.upperBound...])
        let nextSection = try NSRegularExpression(pattern: #"(?m)^\["#)
            .firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder))
        let end = nextSection.flatMap { Range($0.range, in: remainder)?.lowerBound } ?? remainder.endIndex
        let body = String(remainder[..<end])
        let keyPattern = try NSRegularExpression(pattern: #"(?m)^[ \t]*enabled_models[ \t]*=[ \t]*"#)
        guard let key = keyPattern.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let keyRange = Range(key.range, in: body) else {
            return String(original[..<sectionRange.upperBound]) + "\nenabled_models = []" + remainder
        }
        let start = keyRange.upperBound
        guard start < body.endIndex, body[start] == "[" else {
            throw AutopilotError.message("Cannot read backend.enabled_models for calibration.")
        }
        var quote: Character?
        var escaped = false
        var comment = false
        var closing: String.Index?
        var index = body.index(after: start)
        while index < body.endIndex {
            let character = body[index]
            if comment {
                if character == "\n" { comment = false }
            } else if let delimiter = quote {
                if escaped { escaped = false }
                else if character == "\\" && delimiter == "\"" { escaped = true }
                else if character == delimiter { quote = nil }
            } else if character == "#" { comment = true }
            else if character == "\"" || character == "'" { quote = character }
            else if character == "]" { closing = index; break }
            index = body.index(after: index)
        }
        guard let closing else { throw AutopilotError.message("Unterminated backend.enabled_models array.") }
        let replaced = body[..<start] + "[]" + body[body.index(after: closing)...]
        return String(original[..<sectionRange.upperBound]) + replaced + remainder[end...]
    }
}

@MainActor
struct AutopilotServices {
    var command: ([String]) async throws -> String
    var network: () async throws -> (models: [DarkbloomModelData], capacity: [DarkbloomModelCapacity])
    var daemon: () async throws -> DarkbloomDaemonState?
    var memoryGB: Double
    var machineID: String
    var evaluationInterval: TimeInterval = 60

    static var live: Self {
        Self(command: { arguments in
            let path = try LocalServiceController.shared.fetchDarkbloomLocation()
            let timeout: TimeInterval
            switch arguments.first {
            case "benchmark": timeout = 3600
            case "start" where arguments.contains("--force"): timeout = 180
            case "--version", "models": timeout = 60
            default: timeout = 900
            }
            return try await AutopilotCLI.run(executable: path, arguments: arguments,
                                            timeout: timeout)
        }, network: {
            guard let key = Settings.shared.apiKey, !key.isEmpty else {
                throw AutopilotError.message("Add your Darkbloom API key in Settings before enabling Autopilot.")
            }
            let client = DarkbloomClient(apiKey: key)
            async let models = client.models()
            async let capacity = client.modelCapacity()
            return try await (models.data, capacity.models)
        }, daemon: {
            let service = LocalServiceController.shared
            await service.refreshSnapshot()
            guard let running = service.processIsRunning else {
                throw AutopilotError.message("Cannot determine whether the local daemon is running.")
            }
            guard running else { return nil }
            guard let state = service.daemonState, abs(state.writtenAt.timeIntervalSinceNow) < 30 else {
                throw AutopilotError.message("Local daemon snapshot is missing or stale. Waiting for a fresh snapshot.")
            }
            return state
        }, memoryGB: Double(ProcessInfo.processInfo.physicalMemory) / pow(1024, 3),
             machineID: LocalServiceController.shared.currentMachineSerialNumber ?? Host.current().localizedName ?? "local")
    }
}
#endif
