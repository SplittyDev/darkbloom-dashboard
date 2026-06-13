import Foundation

private let HOST: URL = URL(string: "https://api.darkbloom.dev/v1")!

final class DarkbloomClient {
    let apiKey: String
    let decoder: JSONDecoder
    
    init(apiKey: String) {
        self.apiKey = apiKey
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    private func fetch<T>(_ url: URL) async throws -> T where T: Decodable {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, res) = try await URLSession.shared.data(for: req)
        guard let httpResponse = res as? HTTPURLResponse else {
            print("Bad response for \(req.httpMethod?.uppercased() ?? "GET") \(url)")
            throw DarkbloomAPIError.badResponse
        }
        guard httpResponse.statusCode == 200 else {
            print("Status \(httpResponse.statusCode) for \(req.httpMethod?.uppercased() ?? "GET") \(url)")
            throw switch httpResponse.statusCode {
                case 401, 403: DarkbloomAPIError.unauthorized
                default: DarkbloomAPIError.badResponse
            }
        }
        return try decoder.decode(T.self, from: data)
    }
    
    // MARK: Documented API
    
    func stats() async throws -> DarkbloomStats {
        let url = HOST.appending(path: "stats")
        return try await fetch(url)
    }
    
    func attestations() async throws -> DarkbloomAttestations {
        let url = HOST.appending(path: "providers/attestation")
        return try await fetch(url)
    }
    
    func balance() async throws -> DarkbloomBalance {
        let url = HOST.appending(path: "payments/balance")
        return try await fetch(url)
    }
    
    func models() async throws -> DarkbloomModels {
        let url = HOST.appending(path: "models")
        return try await fetch(url)
    }
    
    // MARK: Undocumented API
    
    func accountEarnings() async throws -> DarkbloomAccountEarnings {
        let url = HOST.appending(path: "provider/account-earnings")
        return try await fetch(url)
    }
    
    // MARK: Helpers
    
    func warmupMachine(serialNumber: String, models: [String]) async throws {
        for model in models {
            let url = HOST
                .appending(path: "chat/completions")
                .appending(queryItems: [URLQueryItem(name: "serial", value: serialNumber)])
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.httpBody = """
            {
                "model": "\(model)",
                "messages": [
                    { "role": "user", "content": "Hello" }
                ],
                "stream": false,
                "provider_serial": "\(serialNumber)"
            }
            """.data(using: .utf8)
            print("Warming up \(model) for \(serialNumber)...")
            let (data, res) = try await URLSession.shared.data(for: req)
            if let httpResponse = res as? HTTPURLResponse {
                print("-> Response: HTTP \(httpResponse.statusCode)")
            } else {
                print("-> Error: Response is not HTTP")
            }
            let textData = String(data: data, encoding: .utf8)
            print("-> Data: \(textData ?? "<not utf8>")")
        }
    }
}
