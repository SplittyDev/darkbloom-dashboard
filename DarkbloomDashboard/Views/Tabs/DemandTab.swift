import SwiftUI
import Charts

struct DemandTab: View {
    @Environment(APIDataController.self) private var dataController

    var body: some View {
        Form {
            Section {
                Text("Models are ranked by active and queued requests per routable provider. Higher pressure can mean more opportunity, but earnings are not guaranteed.")
                    .foregroundStyle(.secondary)
            }

            ForEach(dataController.modelCapacities ?? []) { capacity in
                ModelDemandSection(
                    capacity: capacity,
                    name: dataController.models?
                        .first(where: { $0.id == capacity.id })?
                        .metadata.displayName ?? DarkbloomModel(rawValue: capacity.id).displayName
                )
            }
        }
        .formStyle(.grouped)
    }
}

private struct ModelDemandSection: View {
    struct Metric: Identifiable {
        let name: String
        let value: Int

        var id: String { name }
    }

    let capacity: DarkbloomModelCapacity
    let name: String

    private var metrics: [Metric] {
        [
            Metric(name: "Routable providers", value: capacity.routableProviders),
            Metric(name: "Active demand", value: capacity.demand),
        ]
    }

    var body: some View {
        Section {
            Chart(metrics) { metric in
                BarMark(
                    x: .value("Count", metric.value),
                    y: .value("Metric", metric.name)
                )
                .foregroundStyle(by: .value("Metric", metric.name))
            }
            .chartLegend(.hidden)
            .frame(height: 100)

            LabeledContent("Demand pressure") {
                Text(capacity.demandPerRoutableProvider, format: .number.precision(.fractionLength(1)))
                + Text("×")
            }
            LabeledContent("Warm providers", value: capacity.warmProviders.formatted())
            LabeledContent("Queue", value: "\(capacity.queuedRequests) / \(capacity.queueLimit)")
            LabeledContent("Combined speed") {
                Text(capacity.aggregateTps, format: .number.notation(.compactName))
                + Text(" tok/s")
            }
        } header: {
            HStack {
                Text(name)
                Spacer()
                Text(capacity.canAccept ? "Accepting traffic" : "At capacity")
                    .foregroundStyle(capacity.canAccept ? .green : .orange)
            }
        }
    }
}

#Preview(traits: .controllers) {
    DemandTab()
        .frame(minHeight: 600)
}
