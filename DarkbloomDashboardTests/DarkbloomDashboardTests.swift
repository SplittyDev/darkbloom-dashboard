//
//  Darkbloom_DashboardTests.swift
//  Darkbloom DashboardTests
//
//  Created by Marco Quinten on 5/30/26.
//

import Foundation
import Testing
@testable import DarkbloomDashboard

@MainActor
struct Darkbloom_DashboardTests {

    #if os(macOS)
    @Test func daemonStateDecodesSnapshot() throws {
        let data = Data(#"""
        {
          "written_at": 1787502914.682691,
          "capacity": {
            "gpu_memory_active_gb": 36.09446296747774,
            "gpu_memory_cache_gb": 1.8107854183763266,
            "total_memory_gb": 128
          },
          "schema": 1,
          "current_model": "gemma-4-26b-qat-4bit",
          "trust": {
            "status": "online",
            "received_at": 1787500905.6665158,
            "reason": "MDM verification passed",
            "trust_level": "hardware"
          },
          "pid": 42725,
          "version": "0.8.10",
          "slots": [{
            "kv_backend_requested": "auto",
            "mtp_enabled": true,
            "kv_backend": "contiguous",
            "mtp_active": true,
            "model": "gemma-4-26b-qat-4bit"
          }],
          "warm_models": ["gemma-4-26b-qat-4bit"],
          "started_at": 1787500857.372333,
          "process_identity": {
            "pid": 42725,
            "start_time_micros": 1787500819063788
          },
          "stats": {
            "usage_gaps": 0,
            "tokens_generated": 42379,
            "requests_served": 372
          },
          "inference_active": true
        }
        """#.utf8)

        let state = try DarkbloomDaemonState.decode(from: data)

        #expect(state.version == "0.8.10")
        #expect(state.currentModel == "gemma-4-26b-qat-4bit")
        #expect(state.capacity.totalMemoryGb == 128)
        #expect(state.trust.trustLevel == "hardware")
        #expect(state.slots.first?.kvBackend == "contiguous")
        #expect(state.stats.requestsServed == 372)
        #expect(state.inferenceActive)
    }
    #endif

    @Test func trustedMachineHasNoTrustRepairActions() async throws {
        let trust = MachineTrustInfo.trustedFixture()

        #expect(trust.reducedTrustReasons.isEmpty)
    }

    @Test func reducedTrustReasonsExplainFailingTrustChecks() async throws {
        let trust = MachineTrustInfo.trustedFixture(
            status: .untrusted,
            trustLevel: .selfSigned,
            attested: false,
            authenticatedRootEnabled: false,
            mdaVerified: false,
            mdmVerified: false,
            runtimeVerified: false
        )

        #expect(trust.reducedTrustReasons.map(\.title) == [
            "Provider is untrusted",
            "Hardware trust is missing",
            "Attestation is stale",
            "MDA is not verified",
            "MDM is not verified",
            "Authenticated Root is disabled",
            "Runtime verification failed"
        ])
    }
}

private extension MachineTrustInfo {
    static func trustedFixture(
        status: DarkbloomProviderStatus = .serving,
        trustLevel: DarkbloomProviderTrustLevel = .hardware,
        attested: Bool = true,
        acmeVerified: Bool = true,
        authenticatedRootEnabled: Bool = true,
        mdaSerial: String? = "fixture-mda",
        mdaVerified: Bool = true,
        mdmVerified: Bool = true,
        secureBootEnabled: Bool = true,
        secureEnclave: Bool = true,
        sipEnabled: Bool = true,
        runtimeVerified: Bool = true
    ) -> MachineTrustInfo {
        MachineTrustInfo(
            status: status,
            trustLevel: trustLevel,
            attested: attested,
            acmeVerified: acmeVerified,
            authenticatedRootEnabled: authenticatedRootEnabled,
            mdaSerial: mdaSerial,
            mdaVerified: mdaVerified,
            mdmVerified: mdmVerified,
            secureBootEnabled: secureBootEnabled,
            secureEnclave: secureEnclave,
            sipEnabled: sipEnabled,
            runtimeVerified: runtimeVerified
        )
    }
}
