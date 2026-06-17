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
