#if os(macOS)

import SwiftUI
import FiveKit
import OSLog

struct LogsTab: View {
    @Environment(LocalLogController.self) private var viewModel
    
    var body: some View {
        Form {
            Section {
                if viewModel.logs.isEmpty {
                    Text("Waiting for logs to come in...")
                } else {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        IndexedForEach(viewModel.logs.sorted(by: \.date, ascending: false)) { (index, entry) in
                            if index > 0 {
                                Divider()
                            }
                            LogEntryView(entry: entry)
                        }
                    }
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
