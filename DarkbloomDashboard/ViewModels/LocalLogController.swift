#if os(macOS)

import Foundation
import FuzzySearch
import OSLog

nonisolated struct DarkbloomLogEntry: Equatable, Identifiable, Sendable {
    let id: UUID
    let date: Date
    let message: String
    let category: String
    let level: OSLogEntryLog.Level
    
    init(date: Date, message: String, category: String, level: OSLogEntryLog.Level) {
        self.id = UUID()
        self.date = date
        self.message = message
        self.category = category
        self.level = level
    }
    
    init(from osLogEntry: OSLogEntryLog) {
        self.id = UUID()
        self.date = osLogEntry.date
        self.message = osLogEntry.composedMessage
        self.category = osLogEntry.category
        self.level = osLogEntry.level
    }
}

extension DarkbloomLogEntry: Searchable {
    var searchDescriptor: SearchDescriptor {
        SearchDescriptor(message)
    }
}

@MainActor @Observable
final class LocalLogController {
    static let shared = LocalLogController()
    
    private let subsystem = "dev.darkbloom.provider"
    private let maxLogEntries: Int = 2_000
    
    private(set) var logs: [DarkbloomLogEntry] = []
    private(set) var lastFetchDate = Date.now
    private(set) var isUpdating: Bool = false
    
    private var streamTask: Task<Void, Never>?
    private var didFetchHistoricalLogs: Bool = false
    
    var unseenLogCount: Int = 0
    
    private init() {}
    
    func startStreaming() {
        streamTask?.cancel()
        streamTask = Task {
            
            // Fetch historical logs
            if !self.didFetchHistoricalLogs {
                self.isUpdating = true
                if let historicalLogs = try? await fetchOlderLogs() {
                    logs.append(contentsOf: historicalLogs.map(DarkbloomLogEntry.init))
                    
                    if let latest = historicalLogs.last?.date {
                        lastFetchDate = latest.addingTimeInterval(0.001)
                    }
                    
                    if logs.count > maxLogEntries {
                        logs.removeFirst(logs.count - maxLogEntries)
                    }
                }
                self.didFetchHistoricalLogs = true
                self.isUpdating = false
            }
            
            // Keep fetching latest logs
            while !Task.isCancelled {
                self.isUpdating = true
                
                guard let newEntries = try? await fetchLogsSince(lastFetchDate) else {
                    self.isUpdating = false
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                
                if let latest = newEntries.last?.date {
                    lastFetchDate = latest.addingTimeInterval(0.001)
                }
                
                logs.append(contentsOf: newEntries.map(DarkbloomLogEntry.init))
                
                if NavigationController.shared.activeTab != .logs {
                    unseenLogCount += newEntries.count
                }
                
                if logs.count > maxLogEntries {
                    logs.removeFirst(logs.count - maxLogEntries)
                }
                
                self.isUpdating = false
                
                if NavigationController.shared.activeTab == .logs {
                    try? await Task.sleep(for: .seconds(1))
                } else {
                    // When logs aren't being watched, there is no point in checking them every second.
                    try? await Task.sleep(for: .seconds(15))
                }
            }
        }
    }
    
    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }
    
    @concurrent private func fetchOlderLogs() async throws -> [OSLogEntryLog] {
        let store = try OSLogStore(scope: .system)
        let position = store.position(timeIntervalSinceEnd: -24 * 60 * 60)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        let entries = try store.getEntries(at: position, matching: predicate)
        return entries.compactMap { entry in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            return logEntry
        }
        .sorted { $0.date < $1.date }
    }
    
    @concurrent private func fetchLogsSince(_ date: Date) async throws -> [OSLogEntryLog] {
        let store = try OSLogStore(scope: .system)
        let position = store.position(date: date)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        let entries = try store.getEntries(at: position, matching: predicate)
        return entries.compactMap { entry in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            return logEntry
        }
        .sorted { $0.date < $1.date }
    }
}

#endif
