import SwiftUI
import FiveKit

struct SSHConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var connectionInfo = SSHConnectionInfo(user: "", host: "")
    
    @State private var passwordlessLogin: Bool = true
    @State private var password: String = ""
    
    let machine: MachineModel
    
    private func prepare() {
        if passwordlessLogin {
            try? SSHPasswordKeychain.deletePassword(id: machine.serialNo)
            connectionInfo.passwordKeychainId = nil
        } else {
            try? SSHPasswordKeychain.savePassword(password, id: machine.serialNo)
            connectionInfo.passwordKeychainId = machine.serialNo
        }
        machine.sshConnectionInfo = connectionInfo
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        TextField("", text: $connectionInfo.host, prompt: Text("Hostname or IP Address"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    } label: {
                        Text("Host")
                    }
                    
                    LabeledContent {
                        TextField("", text: $connectionInfo.user, prompt: Text("macOS Username"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                    } label: {
                        Text("User")
                    }
                    
                    LabeledContent {
                        Picker("Login Method", selection: $passwordlessLogin.animation()) {
                            Text("Passwordless").tag(true)
                            Text("Password").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    } label: {
                        Text("Login Method")
                    }
                    
                    if !passwordlessLogin {
                        LabeledContent {
                            SecureField("", text: $password, prompt: Text("SSH Password"))
                                .textFieldStyle(.roundedBorder)
                                .labelsHidden()
                        } label: {
                            Text("Password")
                        }
                        .transition(.opacity)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Configure Remote Access")
            .toolbar {
                CancelButton {
                    dismiss()
                }
                
                ConfirmButton {
                    prepare()
                    dismiss()
                }
            }
        }
    }
}
