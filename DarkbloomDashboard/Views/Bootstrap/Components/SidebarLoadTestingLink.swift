#if os(macOS)

import SwiftUI
import FiveKit

struct SidebarLoadTestingLink: View {
    @Environment(LoadTestingController.self) private var viewModel
    
    var body: some View {
        let value = SidebarTab.loadGenerator
        NavigationLink(value: value) {
            HStack {
                Label(value.title, systemImage: value.systemImage)
                Spacer()
                if viewModel.inProgress {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                }
            }
            .animation(.smooth, value: viewModel.inProgress)
        }
    }
}

#Preview(traits: .controllers) {
    List {
        SidebarLoadTestingLink()
    }
    .listStyle(.sidebar)
}

#endif
