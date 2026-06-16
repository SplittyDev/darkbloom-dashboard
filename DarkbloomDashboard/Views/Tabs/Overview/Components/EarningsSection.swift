import SwiftUI

extension OverviewTab {
    struct EarningsSection: View {
        @Environment(APIDataController.self) private var dataController
        @Environment(EarningsController.self) private var earningsController
        
        var body: some View {
            Section {
                LabeledContent {
                    Group {
                        if let earnings = dataController.accountEarnings {
                            Text(MicroUSD.format(earnings.availableBalanceMicroUsd))
                                .foregroundStyle(.primary)
                                .privacySensitive()
                        } else {
                            Text(MicroUSD.format(MicroUSD.fromUsd(10.0)))
                                .redacted(reason: .placeholder)
                        }
                    }
                    .transition(.opacity)
                } label: {
                    Text("Account Balance")
                }
                
                LabeledContent {
                    Group {
                        if let earnings = dataController.accountEarnings {
                            Text(MicroUSD.format(earnings.withdrawableBalanceMicroUsd))
                                .foregroundStyle(.primary)
                                .privacySensitive()
                        } else {
                            Text(MicroUSD.format(MicroUSD.fromUsd(10.0)))
                                .redacted(reason: .placeholder)
                        }
                    }
                    .transition(.opacity)
                } label: {
                    Text("Withdrawable Balance")
                }
                
                if let projectedEarnings = earningsController.projectedEarnings,
                   let monthlyProjection = projectedEarnings.weightedMonthlyProjection {
                    let value1m = monthlyProjection.formatted(.currency(code: "USD"))
                    LabeledContent {
                        Text("\(value1m) / month")
                            .privacySensitive()
                    } label: {
                        Text("Estimated Earnings")
                    }
                    .transition(.opacity)
                }
            } header: {
                Label("Finances", systemImage: "dollarsign.gauge.chart.leftthird.topthird.rightthird")
            }
            .animation(.default, value: dataController.accountEarnings)
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
