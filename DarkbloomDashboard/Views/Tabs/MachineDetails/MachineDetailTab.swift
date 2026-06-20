import SwiftUI
import FiveKit

struct MachineDetailTab: View {
    @Environment(APIDataController.self) private var dataController
    
    @State private var lastMachineInfo: MachineInfo?
    
    let machine: MachineModel
    
    @ViewBuilder private var providerIdSection: some View {
        Section {
            LabeledContent {
                if let providerId = machine.currentInfo?.providerId {
                    Text(providerId)
                        .privacySensitive()
                        .textSelection(.disabled)
                        .contentShape(.rect)
                        .contextMenu {
                            CopyButton(value: providerId)
                        }
                } else {
                    Text("00000000-0000-0000-0000-000000000000")
                        .redacted(reason: .placeholder)
                }
            } label: {
                Text("Provider ID")
            }
        }
    }
    
    var body: some View {
        Form {
            providerIdSection
            MonitoringSection(machine: machine)
            
            if let info = machine.currentInfo ?? lastMachineInfo {
                HardwareSection(hardware: info.hardware)
                
                #if os(macOS)
                TrustSection(trust: info.trust, showAll: true)
                #else
                TrustSection(trust: info.trust, showAll: false)
                #endif
                
                NetworkSection(machine: machine, activity: info.activity)
            }
        }
        .formStyle(.grouped)
        .onChange(of: machine.currentInfo, initial: true) {
            if let currentInfo = machine.currentInfo {
                lastMachineInfo = currentInfo
            }
        }
    }
}

struct VerbatimStringParseStrategy: ParseStrategy {
    typealias ParseInput = String
    typealias ParseOutput = String
    
    func parse(_ value: String) throws -> String {
        value
    }
}

struct CleanStringFormatStyle: ParseableFormatStyle {
    typealias Strategy = VerbatimStringParseStrategy
    typealias FormatInput = String
    typealias FormatOutput = String
    
    var parseStrategy: VerbatimStringParseStrategy {
        VerbatimStringParseStrategy()
    }
    
    func format(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension ParseableFormatStyle where Self == CleanStringFormatStyle {

    static var cleanString: CleanStringFormatStyle {
        CleanStringFormatStyle()
    }
}

#Preview(traits: .controllers) {
    MachineDetailTab(machine: MachineModel(serialNo: "NJD6MGW279"))
}
