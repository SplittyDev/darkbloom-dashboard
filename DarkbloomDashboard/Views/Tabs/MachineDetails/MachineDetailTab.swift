import SwiftUI
import FiveKit

struct MachineDetailTab: View {
    @Environment(APIDataController.self) private var dataController
    
    @State private var lastMachineInfo: MachineInfo?
    
    let machine: MachineModel
    
    var body: some View {
        Form {
            if let info = machine.currentInfo ?? lastMachineInfo {
                Section {
                    LabeledContent {
                        Text(info.providerId)
                    } label: {
                        Text("Provider ID")
                    }
                }
                MonitoringSection(machine: machine)
                HardwareSection(hardware: info.hardware)
                #if os(macOS)
                TrustSection(trust: info.trust, showAll: true)
                #else
                TrustSection(trust: info.trust, showAll: false)
                #endif
                NetworkSection(serialNo: machine.serialNo, activity: info.activity)
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
