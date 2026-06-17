#if os(macOS)

import Foundation
import OpenAI

@MainActor @Observable
final class LoadTestingController {
    static let shared = LoadTestingController()
    
    private let requestsPerApiKeyPerWave = 2
    
    private(set) var inProgress: Bool = false
    
    private(set) var requestsDone: Int = 0
    private(set) var requestsInFlight: Int = 0
    private(set) var requestsFailed: Int = 0
    
    var requestsToSend: Int = 20
    var responses: [ChatResult] = []
    
    private init() {}
    
    func run(apiKeys: [String], payload: String, maxConcurrency: Int, minDelay: Int) async throws {
        guard !inProgress else { return }
        
        let apiKeys = apiKeys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let requestsToSend = max(0, requestsToSend)
        
        guard !apiKeys.isEmpty, requestsToSend > 0 else { return }
        
        inProgress = true
        requestsDone = 0
        requestsInFlight = 0
        requestsFailed = 0
        responses = []
        defer {
            inProgress = false
            requestsInFlight = 0
        }
        
        let minDelay = max(0, minDelay)
        let requestsPerWave = apiKeys.count * requestsPerApiKeyPerWave
        
        var scheduledRequests = 0
        while scheduledRequests + requestsPerWave <= requestsToSend {
            if scheduledRequests > 0, minDelay > 0 {
                try? await Task.sleep(for: .seconds(minDelay))
            }
            
            let waveResults = await sendWave(apiKeys: apiKeys, payload: payload)
            scheduledRequests += requestsPerWave
            
            var retryDelayMilliseconds: Int?
            var shouldAbort = false
            
            for result in waveResults {
                switch result {
                case .success(let response):
                    requestsDone += 1
                    responses.append(response)
                case .failure(let delay):
                    requestsFailed += 1
                    if let delay {
                        retryDelayMilliseconds = max(retryDelayMilliseconds ?? 0, delay)
                    } else {
                        shouldAbort = true
                    }
                }
            }
            
            if shouldAbort {
                break
            }
            
            if let retryDelayMilliseconds, scheduledRequests + requestsPerWave <= requestsToSend {
                try? await Task.sleep(for: .milliseconds(retryDelayMilliseconds))
            }
        }
    }
    
    private func sendWave(apiKeys: [String], payload: String) async -> [WaveResult] {
        await withTaskGroup(of: WaveResult.self) { group in
            for apiKey in apiKeys {
                for _ in 0..<requestsPerApiKeyPerWave {
                    group.addTask {
                        await self.sendRequest(apiKey: apiKey, payload: payload)
                    }
                }
            }
            
            var results: [WaveResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }
    
    private func sendRequest(apiKey: String, payload: String) async -> WaveResult {
        let config = OpenAI.Configuration(
            token: apiKey,
            host: "api.darkbloom.dev",
            scheme: "https",
            basePath: "/v1",
            parsingOptions: .relaxed
        )
        let client = OpenAI(configuration: config)
        let query = ChatQuery(
            messages: [
                .user(.init(content: .string(payload)))
            ],
            model: "gpt-oss-20b"
        )
        
        requestsInFlight += 1
        defer { requestsInFlight -= 1 }
        
        do {
            return .success(try await client.chats(query: query))
        } catch {
            print(error)
            return .failure(Self.retryDelayMilliseconds(for: error))
        }
    }
    
    nonisolated private static func retryDelayMilliseconds(for error: any Error) -> Int? {
        if let apiError = error as? APIErrorResponse {
            return retryDelayMilliseconds(from: apiError.error.message)
        }
        
        return retryDelayMilliseconds(from: String(describing: error))
    }
    
    nonisolated private static func retryDelayMilliseconds(from message: String) -> Int? {
        guard let range = message.range(of: "retry after ", options: .caseInsensitive) else {
            return nil
        }
        
        var rawSeconds = ""
        for character in message[range.upperBound...] {
            if character.isNumber || character == "." {
                rawSeconds.append(character)
            } else if !rawSeconds.isEmpty {
                break
            }
        }
        
        guard let seconds = Double(rawSeconds), seconds > 0 else {
            return nil
        }
        
        return max(1, Int((seconds * 1_000).rounded(.up)))
    }
}

private enum WaveResult {
    case success(ChatResult)
    case failure(Int?)
}

#endif
