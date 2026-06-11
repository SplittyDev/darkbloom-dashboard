import SwiftUI

struct CompactTrustIndicator: View {
    let machine: MachineModel
    
    @ViewBuilder private var offlineIndicator: some View {
        Text(Image(systemName: "circle.fill"))
            .foregroundStyle(Color.red)
    }
    
    var body: some View {
        if let info = machine.currentInfo {
            if info.trust.isOnline {
                Group {
                    if info.trust.isTrusted {
                        Text(Image(systemName: "checkmark.shield.fill"))
                    } else {
                        Text(Image(systemName: "shield.slash.fill"))
                            .foregroundStyle(Color.yellow)
                    }
                }
                .transition(.blurReplace)
            } else {
                offlineIndicator
                    .transition(.blurReplace)
            }
        } else {
            offlineIndicator
                .transition(.blurReplace)
        }
    }
}
