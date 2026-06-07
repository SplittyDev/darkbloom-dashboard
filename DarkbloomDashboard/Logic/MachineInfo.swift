import Foundation

struct MachineInfo: Equatable {
    let providerId: String
    let serialNumber: String
    let trust: MachineTrustInfo
    let hardware: MachineHardwareInfo
    let activity: MachineActivityInfo
}

struct MachineTrustInfo: Equatable {
    let status: DarkbloomProviderStatus
    let trustLevel: DarkbloomProviderTrustLevel
    let attested: Bool
    let acmeVerified: Bool
    let authenticatedRootEnabled: Bool
    let mdaSerial: String?
    let mdaVerified: Bool
    let mdmVerified: Bool
    let secureBootEnabled: Bool
    let secureEnclave: Bool
    let sipEnabled: Bool
    let runtimeVerified: Bool
    
    var isOnline: Bool {
        let onlineStatus: Set<DarkbloomProviderStatus> = [.online, .serving]
        return onlineStatus.contains(status)
    }
    
    /// Returns whether the machine is likely to be in a trusted state.
    var isTrusted: Bool {
        let trustedStatus: Set<DarkbloomProviderStatus> = [.online, .serving]
        let isTrustedStatus = trustedStatus.contains(status)
        let isTrustedHardware = trustLevel == .hardware
        let isTrustedEnvironment = authenticatedRootEnabled && secureEnclave && secureBootEnabled && sipEnabled
        let isMdaAndMdmVerified = mdaVerified && mdmVerified
        return (
            isTrustedStatus
            && isTrustedHardware
            && isTrustedEnvironment
            && isMdaAndMdmVerified
            && runtimeVerified
            && attested
        )
    }

    var reducedTrustReasons: [TrustReductionReason] {
        var reasons: [TrustReductionReason] = []

        if !isOnline {
            reasons.append(
                TrustReductionReason(
                    title: "Provider is untrusted",
                    explanation: "Darkbloom is not reporting this provider as online or serving.",
                    recoveryAction: "Restart the Darkbloom provider, wait for it to reconnect, then refresh the dashboard."
                )
            )
        }

        if trustLevel != .hardware {
            reasons.append(
                TrustReductionReason(
                    title: "Hardware trust is missing",
                    explanation: "The provider is not currently using hardware-backed trust.",
                    recoveryAction: "Confirm this Mac is enrolled correctly and that the provider is running on the expected Apple silicon machine."
                )
            )
        }

        if !attested {
            reasons.append(
                TrustReductionReason(
                    title: "Attestation is stale",
                    explanation: "The network has not accepted a fresh attestation for this provider.",
                    recoveryAction: "Restart the provider and wait for a new challenge to complete."
                )
            )
        }

        if !mdaVerified {
            reasons.append(
                TrustReductionReason(
                    title: "MDA is not verified",
                    explanation: "Mobile Device Attestation is not verified for this Mac.",
                    recoveryAction: "Check that the Mac can complete Apple attestation and that its serial matches the tracked machine."
                )
            )
        }

        if !mdmVerified {
            reasons.append(
                TrustReductionReason(
                    title: "MDM is not verified",
                    explanation: "Darkbloom is not seeing the expected device-management verification.",
                    recoveryAction: "Confirm the machine is still enrolled in the required management profile, then restart the provider."
                )
            )
        }

        if !authenticatedRootEnabled {
            reasons.append(
                TrustReductionReason(
                    title: "Authenticated Root is disabled",
                    explanation: "macOS authenticated root is disabled.",
                    recoveryAction: "Re-enable authenticated root/Signed System Volume protection, reboot, then restart Darkbloom."
                )
            )
        }

        if !secureBootEnabled {
            reasons.append(
                TrustReductionReason(
                    title: "Secure Boot is disabled",
                    explanation: "Secure Boot is not enabled for this machine.",
                    recoveryAction: "Enable full security in Startup Security Utility, reboot, then restart Darkbloom."
                )
            )
        }

        if !secureEnclave {
            reasons.append(
                TrustReductionReason(
                    title: "Secure Enclave is unavailable",
                    explanation: "The provider is not reporting Secure Enclave support.",
                    recoveryAction: "Verify this is the expected Apple silicon Mac and restart the provider after any OS update."
                )
            )
        }

        if !sipEnabled {
            reasons.append(
                TrustReductionReason(
                    title: "SIP is disabled",
                    explanation: "System Integrity Protection is disabled.",
                    recoveryAction: "Boot to recoveryOS, re-enable SIP, reboot, then restart Darkbloom."
                )
            )
        }

        if !runtimeVerified {
            reasons.append(
                TrustReductionReason(
                    title: "Runtime verification failed",
                    explanation: "Darkbloom has not verified the current provider runtime.",
                    recoveryAction: "Restart the provider and let the next runtime verification challenge complete."
                )
            )
        }

        return reasons
    }
}

struct TrustReductionReason: Equatable, Identifiable {
    var id: String { title }

    let title: String
    let explanation: String
    let recoveryAction: String
}

struct MachineHardwareInfo: Equatable {
    let modelIdentifier: String
    let chipName: String
    let cpuCores: DarkbloomCPUCoreInfo
    let gpuCores: Int
    let memoryGb: Int
    let memoryBandwidthGbs: Int
    
    var modelDisplayName: String {
        if let model = ModelIdentifier(rawValue: modelIdentifier) {
            model.displayName
        } else {
            "\(modelIdentifier) (\(chipName))"
        }
    }
}

struct MachineActivityInfo: Equatable {
    let requestsServed: Int
    let tokensGenerated: Int
    let lastChallengeVerified: String
    let failedChallenges: Int
    let models: [DarkbloomModel]
    
    var lastChallengeDate: Date? {
        guard !lastChallengeVerified.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: lastChallengeVerified)
    }
}
