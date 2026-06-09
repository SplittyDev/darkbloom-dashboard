import SwiftUI
import Charts
import MapKit
import FiveKit

struct NetworkTab: View {
    @Environment(APIDataController.self) private var dataController
    
    var body: some View {
        Form {
            if let stats = dataController.stats {
                NetworkStatsSection(stats: stats)
                TrafficTimeSeriesSection(stats: stats)
                TokenDistributionSection(stats: stats)
                TrafficFlowSection(stats: stats)
            }
        }
        .formStyle(.grouped)
    }
}

#Preview(traits: .controllers) {
    NetworkTab()
        .frame(minHeight: 600)
}
