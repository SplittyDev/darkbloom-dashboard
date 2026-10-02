#if os(macOS)

import SwiftUI
import FiveKit

struct SidebarAutopilotLink: View {
    @State private var controller = AutopilotController.shared

    private var needsAttention: Bool {
        controller.lastError != nil || controller.calibrationWarning != nil || controller.saved.pendingChange != nil
    }

    private var indicatorColor: Color {
        if controller.isEnabled {
            needsAttention ? .orange : .primary
        } else {
            controller.lastError == nil ? .secondary : .red
        }
    }

    private var indicatorSymbol: String {
        if controller.lastError != nil || (controller.isEnabled && controller.calibrationWarning != nil) {
            "exclamationmark.triangle.fill"
        } else if controller.isEnabled {
            controller.saved.pendingChange == nil ? "checkmark.circle.fill" : "arrow.clockwise.circle.fill"
        } else {
            "pause.circle.fill"
        }
    }

    private var explanation: String {
        let engagement = controller.isEnabled ? "Autopilot is engaged." : "Autopilot is not engaged."
        let detail = controller.lastError ?? (controller.isEnabled ? controller.calibrationWarning : nil)
        return [engagement, controller.status, detail].compactMap { $0 }.joined(separator: " ")
    }

    var body: some View {
        let value = SidebarTab.autopilot
        NavigationLink(value: value) {
            HStack {
                Label(value.title, systemImage: value.systemImage)
                Spacer()
                Text(Image(systemName: indicatorSymbol))
                    .foregroundStyle(indicatorColor)
                    .fixedSize()
                    .accessibilityLabel(controller.isEnabled ? "Autopilot engaged" : "Autopilot not engaged")
                    .accessibilityValue(controller.status)
            }
            .animation(.smooth, value: controller.isEnabled)
            .animation(.smooth, value: needsAttention)
        }
        .help(explanation)
    }
}

#Preview(traits: .controllers) {
    List {
        SidebarAutopilotLink()
    }
    .listStyle(.sidebar)
}

#endif
