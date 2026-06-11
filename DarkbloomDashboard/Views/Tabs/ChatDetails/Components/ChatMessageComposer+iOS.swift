#if os(iOS)

import SwiftUI
import FiveKit

extension ChatDetailTab {
    private enum FocusedField: Hashable {
        case messageComposer
    }
    
    struct ChatMessageComposer_iOS: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        @Binding var text: String
        
        let canSend: Bool
        let sendMessage: () -> Void
        
        @FocusState private var focusedField: FocusedField?
        
        var body: some View {
            VStack(spacing: 8) {
                HStack {
                    ModelPicker()
                    RoutingPicker()
                    Spacer()
                }
                .controlSize(.small)
                
                HStack {
                    MessageComposerTextField(text: $text)
                        .focused($focusedField, equals: .messageComposer)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                    
                    Button {
                        sendMessage()
                    } label: {
                        Text(Image(systemName: "arrow.up"))
                    }
                    .buttonBorderShape(.circle)
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
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .apply { view in
                    if #available(iOS 26, *) {
                        view
                            .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    } else {
                        view
                            .background(.thinMaterial)
                            .clipShape(.rect(cornerRadius: 24))
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now().advanced(by: .milliseconds(100))) {
                        focusedField = .messageComposer
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffectContainer()
        }
    }
    
    struct ModelPicker: View {
        @Environment(ChatViewModel.self) private var viewModel
        
        var body: some View {
            @Bindable var viewModel = self.viewModel
            
            Menu {
                ForEach(DarkbloomModel.recommendedCases) { model in
                    Button {
                        viewModel.chat.model = model
                    } label: {
                        Label {
                            Text(model.displayName)
                        } icon: {
                            if viewModel.chat.model == model {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label {
                    Text(viewModel.chat.model.displayName)
                } icon: {
                    Image(systemName: "cube.transparent")
                }
            }
            .menuOrder(.fixed)
            .apply { view in
                if #available(iOS 26, *) {
                    view.buttonStyle(.glass)
                } else {
                    view.buttonStyle(.bordered)
                }
            }
        }
    }
    
    struct RoutingPicker: View {
        @Environment(\.redactionReasons) private var redactionReasons
        
        @Environment(ChatViewModel.self) private var viewModel
        @Environment(APIDataController.self) private var dataController
        @Environment(FleetController.self) private var fleetController
        
        private let settings = Settings.shared
        
        var body: some View {
            @Bindable var viewModel = self.viewModel
            
            Menu {
                Button {
                    viewModel.chat.routing = .auto
                } label: {
                    Label {
                        Text("Auto Routing")
                    } icon: {
                        if case .auto = viewModel.chat.routing {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button {
                    viewModel.chat.routing = .anyFleet
                } label: {
                    Label {
                        Text("Any Fleet Member")
                    } icon: {
                        if case .anyFleet = viewModel.chat.routing {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                ForEach(fleetController.machineSerialNumbers) { serialNo in
                    Button {
                        viewModel.chat.routing = .only(serialNo)
                    } label: {
                        Label {
                            let displaySerialNo = redactionReasons.contains(.privacy) ? "hidden" : serialNo
                            if let resolvedMachine = dataController.machineInfo[serialNo] {
                                let displayName = resolvedMachine.hardware.modelDisplayName
                                Text(displayName)
                            } else {
                                Text(displaySerialNo)
                            }
                        } icon: {
                            if case .only(serialNo) = viewModel.chat.routing {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label {
                    let value: String = {
                        switch viewModel.chat.routing {
                            case .auto: return "Auto"
                            case .anyFleet: return "Fleet"
                            case .anyOf: return "Fleet Set"
                            case .only(let serialNo):
                                let displaySerialNo = redactionReasons.contains(.privacy) ? "hidden" : serialNo
                                if let resolvedMachine = dataController.machineInfo[serialNo] {
                                    let displayName = resolvedMachine.hardware.modelDisplayName
                                    return displayName
                                } else {
                                    return displaySerialNo
                                }
                        }
                    }()
                    Text(value)
                } icon: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
            }
            .menuOrder(.fixed)
            .apply { view in
                if #available(iOS 26, *) {
                    view.buttonStyle(.glass)
                } else {
                    view.buttonStyle(.bordered)
                }
            }
        }
    }
}

#Preview(traits: .controllers) {
    @Previewable @State var text: String = ""
    
    ScrollView {
    }
    .safeAreaBarOrInset(edge: .bottom) {
        ChatDetailTab.ChatMessageComposer_iOS(
            text: $text,
            canSend: !text.isEmpty,
            sendMessage: {}
        )
    }
    .environment(ChatViewModel.get())
}

#endif
