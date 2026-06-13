#if os(macOS)

import SwiftUI
import FiveKit
import FuzzySearch
import OSLog

enum LogLevelMapping: String, Identifiable, CaseIterable, Hashable {
    case undefined
    case debug
    case info
    case notice
    case error
    case fault
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
            case .undefined: "Undefined"
            case .debug: "Debug"
            case .info: "Info"
            case .notice: "Warning"
            case .error: "Error"
            case .fault: "Critical"
        }
    }
    
    var osLogLevel: OSLogEntryLog.Level {
        switch self {
            case .undefined: .undefined
            case .debug: .debug
            case .info: .info
            case .notice: .notice
            case .error: .error
            case .fault: .fault
        }
    }
    
    var priority: Int {
        switch self {
            case .undefined: 0
            case .debug: 1
            case .info: 2
            case .notice: 3
            case .error: 4
            case .fault: 5
        }
    }
    
    var includingHigherPriority: Set<LogLevelMapping> {
        var set: Set<LogLevelMapping> = [self]
        for logLevel in Self.allCases where logLevel.priority > self.priority {
            set.insert(logLevel)
        }
        return set
    }
}

struct LogsTab: View {
    @Environment(LocalLogController.self) private var viewModel
    
    @State private var searchText: String = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var filteredLogs: [DarkbloomLogEntry]?
    @State private var activeFilter: LogLevelMapping?
    @State private var logLevelCounts: [OSLogEntryLog.Level: Int] = [:]
    
    private func recalculateLogLevelCounts() {
        var logLevelCounts: [OSLogEntryLog.Level: Int] = [:]
        for log in viewModel.logs {
            logLevelCounts[log.level, default: 0] += 1
        }
        self.logLevelCounts = logLevelCounts
    }
    
    private func reevaluateSearchResults() {
        searchTask?.cancel()
        searchTask = Task {
            let searchableLogs = {
                if let activeFilter {
                    let eligibleLogLevels = activeFilter.includingHigherPriority.map(\.osLogLevel)
                    return viewModel.logs.filter { log in
                        eligibleLogLevels.contains(log.level)
                    }
                } else {
                    return viewModel.logs
                }
            }()
            guard !searchText.isEmpty else {
                self.filteredLogs = searchableLogs
                return
            }
            if Task.isCancelled { return }
            let results = await Fuzzy().search(for: searchText, in: searchableLogs, minimumScore: 0.4)
            if Task.isCancelled { return }
            self.filteredLogs = results.map(\.item)
        }
    }
    
    var body: some View {
        Form {
            Section {
                if viewModel.logs.isEmpty {
                    Text("Waiting for logs to come in...")
                } else {
                    let logs = filteredLogs ?? viewModel.logs
                    LazyVStack(alignment: .leading, spacing: 4) {
                        IndexedForEach(logs.sorted(by: \.date, ascending: false)) { (index, entry) in
                            if index > 0 {
                                Divider()
                            }
                            LogEntryView(entry: entry)
                        }
                    }
                    .animation(.interactiveSpring, value: logs)
                }
            } header: {
                HStack(alignment: .bottom) {
                    Text("Darkbloom Logs")
                    Spacer()
                    LabeledPill {
                        Text("LIVE")
                    } label: {
                        Text(Image(systemName: "record.circle"))
                            .foregroundStyle(Color.green)
                            .phaseAnimator([false, true]) { placeholder, phase in
                                placeholder.opacity(phase ? 1 : 0.75)
                            }
                    }
                    .font(.caption)
                    .controlSize(.small)
                }
            }
            .animation(.interactiveSpring, value: viewModel.logs)
        }
        .formStyle(.grouped)
        .searchable(text: $searchText)
        .onChange(of: viewModel.logs, initial: true) {
            recalculateLogLevelCounts()
        }
        .onChange(of: searchText) {
            reevaluateSearchResults()
        }
        .onChange(of: activeFilter) {
            reevaluateSearchResults()
        }
        .toolbar {
            Menu {
                Picker("", selection: $activeFilter) {
                    Text("Everything")
                        .tag(nil as LogLevelMapping?)
                    Divider()
                    Section {
                        ForEach(LogLevelMapping.allCases) { level in
                            Text("\(level.displayName) (\(logLevelCounts[level.osLogLevel, default: 0]))")
                                .tag(level as LogLevelMapping?)
                        }
                    } header: {
                        Text("Minimum Log Level")
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .symbolVariant(activeFilter != nil ? .circle.fill : .circle)
            }
        }
        .onAppear {
            viewModel.unseenLogCount = 0
        }
    }
}

struct LabeledLogComponent<Content: View, Label: View>: View {
    let content: () -> Content
    let label: () -> Label
    
    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.content = content
        self.label = label
    }
    
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            label()
            Text(verbatim: "|")
            content()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

struct LogEntryView: View {
    let entry: DarkbloomLogEntry
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = false
        formatter.formattingContext = .standalone
        return formatter
    }()
    
    func pillStyle(for logLevel: OSLogEntryLog.Level) -> PillContentStyle {
        switch entry.level {
            case .notice: .warning
            case .error: .negative
            case .fault: .negative
            default: .neutral
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.message)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                LabeledLogComponent {
                    Text(dateFormatter.string(from: entry.date))
                } label: {
                    Text("time")
                }
                LabeledLogComponent {
                    switch entry.level {
                        case .undefined: EmptyView()
                        case .debug: Text("debug")
                        case .info: Text("info")
                        case .notice: Text("notice").foregroundStyle(.yellow)
                        case .error: Text("error").foregroundStyle(.red)
                        case .fault: Text("fault").foregroundStyle(.red)
                        @unknown default: EmptyView()
                    }
                } label: {
                    Text("level")
                }
                LabeledLogComponent {
                    Text(entry.category)
                } label: {
                    Text("category")
                }
            }
            .controlSize(.small)
        }
    }
}

#Preview(traits: .controllers) {
    LogsTab()
}

#endif
