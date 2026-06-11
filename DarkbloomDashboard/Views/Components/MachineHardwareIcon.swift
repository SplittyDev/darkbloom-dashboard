import SwiftUI
import FiveKit

struct MachineHardwareIcon: View {
    let machine: MachineModel
    let size: CGFloat
    
    private var systemImage: String {
        if let info = machine.currentInfo, let model = ModelIdentifier(rawValue: info.hardware.modelIdentifier) {
            model.modelKind.systemImage
        } else {
            "macstudio"
        }
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.systemFill)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.2)
            }
            .animation(.default, value: systemImage)
    }
}
