#if os(macOS)

import SwiftUI
import FiveKit

extension ChatDetailTab {
    struct ChatMessageComposer_macOS: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        @Binding var text: String
        
        let canSend: Bool
        let sendMessage: () -> Void
        
        var body: some View {
            @Bindable var viewModel = self.viewModel
            
            VStack(spacing: 0) {
                MessageComposerTextField(text: $text)
                    .onKeyPress { key in
                        guard key.modifiers.isEmpty && key.key == .return else {
                            return .ignored
                        }
                        sendMessage()
                        return .handled
                    }
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity)
                
                HStack(alignment: .bottom) {
                    ModelPicker()
                    RoutingPicker()
                    
                    Spacer()
                    
                    Button {
                        sendMessage()
                    } label: {
                        Text(Image(systemName: "arrow.up"))
                    }
                    .buttonBorderShape(.circle)
                    .controlSize(.extraLarge)
                    .apply { btn in
                        if #available(iOS 26, macOS 26, *) {
                            if canSend {
                                btn.buttonStyle(.glassProminent)
                            } else {
                                btn.buttonStyle(.glass)
                            }
                        } else {
                            if canSend {
                                btn.buttonStyle(.borderedProminent)
                            } else {
                                btn.buttonStyle(.bordered)
                            }
                        }
                    }
                    .disabled(!canSend || viewModel.inProgress)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .apply { view in
                if #available(iOS 26, macOS 26, *) {
                    view.glassEffect(.regular.tint(Color.systemFill), in: .rect(cornerRadius: 16))
                } else {
                    view
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    struct ModelPicker: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        var body: some View {
            @Bindable var viewModel = self.viewModel
            
            Picker(selection: $viewModel.chat.model) {
                ForEach(DarkbloomModel.recommendedCases) { model in
                    Text(model.displayName)
                        .tag(model)
                }
            } label: {
                Text(Image(systemName: "cube.transparent"))
            }
            .buttonStyle(.plain)
            .pickerStyle(.menu)
            .foregroundStyle(.secondary)
        }
    }
    
    struct RoutingPicker: View {
        @Environment(ChatViewModel.self) private var viewModel
        @Environment(APIDataController.self) private var dataController
        
        private let settings = Settings.shared
        
        var body: some View {
            @Bindable var viewModel = self.viewModel
            
            Picker(selection: $viewModel.chat.routing) {
                Text("Auto Routing").tag(ChatRouting.auto)
                Divider()
                Text("Any Fleet Member").tag(ChatRouting.anyFleet)
                ForEach(settings.trackedMachineSerialNumbers) { serialNo in
                    if let resolvedMachine = dataController.machineInfo[serialNo] {
                        let displayName = resolvedMachine.hardware.modelDisplayName
                        Text("\(displayName) (\(serialNo))").tag(ChatRouting.only(serialNo))
                    } else {
                        Text(serialNo).tag(ChatRouting.only(serialNo))
                    }
                }
            } label: {
                Text(Image(systemName: "point.3.connected.trianglepath.dotted"))
            }
            .buttonStyle(.plain)
            .pickerStyle(.menu)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var text: String = ""
    
    ScrollView {
    }
    .safeAreaBarOrInset(edge: .bottom) {
        ChatDetailTab.ChatMessageComposer_macOS(
            text: $text,
            canSend: !text.isEmpty,
            sendMessage: {}
        )
    }
    .environment(ChatViewModel.get())
    .environment(APIDataController())
}

#endif
