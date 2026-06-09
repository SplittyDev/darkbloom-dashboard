import SwiftUI

extension OverviewTab {
    struct EarningsSection: View {
        @Environment(APIDataController.self) private var dataController
        @Environment(EarningsController.self) private var earningsController
        
        var body: some View {
            Section {
                LabeledContent {
                    Group {
                        if let balance = dataController.balance {
                            Text(balance.formatted)
                                .foregroundStyle(.primary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .transition(.opacity)
                } label: {
                    Text("Account Balance")
                }
                
                if let projectedEarnings = earningsController.projectedEarnings {
                    let value1m = projectedEarnings.projectedEarningsPerMonth.formatted(.currency(code: "USD"))
                    LabeledContent {
                        Text("\(value1m) / month")
                    } label: {
                        Text("Projected Earnings")
                    }
                    .transition(.opacity)
                }
            } header: {
                Label("Finances", systemImage: "dollarsign.gauge.chart.leftthird.topthird.rightthird")
            }
            .animation(.default, value: dataController.balance)
            .animation(.default, value: earningsController.projectedEarnings)
        }
    }
}

#Preview(traits: .controllers) {
    Form {
        OverviewTab.EarningsSection()
    }
    .formStyle(.grouped)
}
