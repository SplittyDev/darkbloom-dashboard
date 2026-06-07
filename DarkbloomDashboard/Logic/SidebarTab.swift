import Foundation

enum SidebarTab: Hashable, Identifiable {
    case overview
    case network
    case models
    case earnings
    case machine(String)
    case machines
    case loadGenerator
    case logs

    var id: String {
        switch self {
            case .overview: "overview"
            case .network: "network"
            case .models: "models"
            case .earnings: "earnings"
            case .machine(let id): "machine-\(id)"
            case .machines: "machines"
            case .loadGenerator: "load-generator"
            case .logs: "logs"
        }
    }

    var title: String {
        switch self {
            case .overview: "Overview"
            case .network: "Network"
            case .models: "Models"
            case .earnings: "Earnings"
            case .machine(let id): id
            case .machines: "Machines"
            case .loadGenerator: "Load Generator"
            case .logs: "Log Viewer"
        }
    }

    var systemImage: String {
        switch self {
            case .overview: "gauge.with.dots.needle.67percent"
            case .network: "network"
            case .models: "list.dash.header.rectangle"
            case .earnings: "dollarsign.gauge.chart.leftthird.topthird.rightthird"
            case .machine: "macstudio"
            case .machines: "macstudio"
            case .loadGenerator: "bolt.fill"
            case .logs: "text.page"
        }
    }
}
