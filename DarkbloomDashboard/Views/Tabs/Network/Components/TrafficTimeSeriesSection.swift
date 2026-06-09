import SwiftUI
import Charts
import FiveKit

extension NetworkTab {
    private struct RequestSeriesEntry: Identifiable {
        let timestamp: Date
        let requests: Int
        
        var id: String {
            "\(timestamp.formatted(.iso8601))-\(requests)"
        }
    }
    
    private struct TokenSeriesEntry: Identifiable {
        let timestamp: Date
        let kind: Kind
        let tokens: Int
        
        var id: String {
            "\(timestamp.formatted(.iso8601))-\(kind.rawValue)"
        }
        
        enum Kind: String {
            case prompt
            case completion
            
            var label: String {
                switch self {
                    case .prompt: "Prompt"
                    case .completion: "Completion"
                }
            }
        }
    }
    
    struct TrafficTimeSeriesSection: View {
        let stats: DarkbloomStats
        
        private var requestSeries: [RequestSeriesEntry] {
            let rawEntries = stats.timeSeries.map {
                RequestSeriesEntry(timestamp: $0.timestamp, requests: $0.requests)
            }
            guard let (firstEntryTime, lastEntryTime) = rawEntries.minmax(byValue: \.timestamp) else {
                return rawEntries
            }
            var consecutiveEntries: [RequestSeriesEntry] = []
            var currentTime = firstEntryTime
            while currentTime < lastEntryTime {
                if let entry = rawEntries.first(where: { $0.timestamp == currentTime }) {
                    consecutiveEntries.append(entry)
                } else {
                    consecutiveEntries.append(RequestSeriesEntry(timestamp: currentTime, requests: 0))
                }
                currentTime = Calendar.current.date(byAdding: .minute, value: 1, to: currentTime)!
            }
            return consecutiveEntries
        }
        
        private var tokenSeries: [TokenSeriesEntry] {
            stats.timeSeries.flatMap { entry in
                [
                    TokenSeriesEntry(timestamp: entry.timestamp, kind: .prompt, tokens: entry.promptTokens),
                    TokenSeriesEntry(timestamp: entry.timestamp, kind: .completion, tokens: entry.completionTokens),
                ]
            }
        }
        
        var body: some View {
            Section {
                HStack(spacing: 16) {
                    
                    // Requests Chart
                    Chart(requestSeries) { entry in
                        LineMark(
                            x: .value("timestamp", entry.timestamp, unit: .minute),
                            y: .value("requests", entry.requests)
                        )
                    }
                    
                    // Tokens Chart
                    Chart(tokenSeries) { entry in
                        BarMark(
                            x: .value("timestamp", entry.timestamp, unit: .minute),
                            y: .value("tokens", entry.tokens),
                            stacking: .standard
                        )
                        .foregroundStyle(by: .value("token kind", entry.kind.label))
                    }
                    .chartForegroundStyleScale([
                        TokenSeriesEntry.Kind.prompt.label: Color.accent,
                        TokenSeriesEntry.Kind.completion.label: Color.green,
                    ])
                    .chartLegend(.hidden)
                }
            } header: {
                HStack(spacing: 16) {
                    
                    // Requests Header
                    VStack(alignment: .leading) {
                        let total = stats.timeSeries.map(\.requests).reduce(0, +)
                        let peak = stats.timeSeries.map(\.requests).max() ?? 0
                        Text("Requests / Minute")
                        Text("\(total) total / \(peak) peak")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Tokens Header
                    VStack(alignment: .leading) {
                        let total = stats.timeSeries.map(\.totalTokens).reduce(0, +)
                        let peak = stats.timeSeries.map(\.totalTokens).max() ?? 0
                        Text("Tokens / Minute")
                        Text("\(total) total / \(peak) peak")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

#Preview(traits: .controllers) {
    @Previewable @Environment(APIDataController.self) var dataController
    
    Form {
        if let stats = dataController.stats {
            NetworkTab.TrafficTimeSeriesSection(stats: stats)
        }
    }
    .formStyle(.grouped)
}
