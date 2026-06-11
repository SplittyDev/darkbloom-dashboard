import SwiftUI

extension MachineDetailTab {
    struct TrustSection: View {
        let trust: MachineTrustInfo
        let showAll: Bool
        
        var body: some View {
            Section {
                LabeledContent {
                    Text(trust.trustLevel.displayName)
                } label: {
                    Text("Trust Level")
                }
                if showAll || !trust.mdaVerified {
                    LabeledContent {
                        Text(trust.mdaVerified ? "Yes" : "No")
                    } label: {
                        Text("Mobile Device Attestation (MDA)")
                    }
                }
                if showAll || !trust.mdmVerified {
                    LabeledContent {
                        Text(trust.mdmVerified ? "Yes" : "No")
                    } label: {
                        Text("Mobile Device Management (MDM)")
                    }
                }
                if showAll || !trust.authenticatedRootEnabled {
                    LabeledContent {
                        Text(trust.authenticatedRootEnabled ? "Yes" : "No")
                    } label: {
                        Text("Authenticated Root")
                    }
                }
                if showAll || !trust.sipEnabled {
                    LabeledContent {
                        Text(trust.sipEnabled ? "Yes" : "No")
                    } label: {
                        Text("System Integrity Protection")
                    }
                }
                if showAll || !trust.secureBootEnabled {
                    LabeledContent {
                        Text(trust.secureBootEnabled ? "Yes" : "No")
                    } label: {
                        Text("Secure Boot")
                    }
                }
                if showAll || !trust.secureEnclave {
                    LabeledContent {
                        Text(trust.secureEnclave ? "Yes" : "No")
                    } label: {
                        Text("Secure Enclave")
                    }
                }
            } header: {
                HStack {
                    Text("Trust & Attestation")
                    Spacer()
                    TrustExplanationButton(trust: trust)
                }
            }
            .animation(.snappy, value: trust)
        }
    }
}
