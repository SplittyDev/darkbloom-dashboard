#if os(macOS)
import Foundation

enum AutopilotRecovery {
    static let retryInterval: TimeInterval = 60
    static let restartConfirmationInterval: TimeInterval = 180
    static let maximumUnconfirmedInterval: TimeInterval = 1800

    static func switchIsBusy(_ error: any Error) -> Bool {
        error.localizedDescription.contains("A provider model switch is already in progress")
    }

    static func switchTimedOut(_ error: any Error) -> Bool {
        let message = error.localizedDescription
        return message.contains("Model-switch drain deadline expired") ||
            message.contains("darkbloom switch timed out") ||
            message.contains("No matching switch completion receipt arrived")
    }

    static func command(for pending: AutopilotPendingChange) -> [String] {
        if pending.forceRestart == true {
            // restart preserves the old selection; start explicitly replaces it.
            return ["start", "--model", pending.model, "--timeout", "0", "--force"]
        }
        return [pending.start ? "start" : "switch", "--model", pending.model]
    }
}
#endif
