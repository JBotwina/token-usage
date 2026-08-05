import Foundation

/// Reads the ElevenLabs character quota. One GET, no billable synthesis.
actor ElevenLabsClient {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// Subset of `/v1/user/subscription` we render. Everything optional but the
    /// two counters — the payload varies by plan tier.
    struct Subscription: Decodable, Sendable {
        var tier: String?
        var status: String?
        var characterCount: Int
        var characterLimit: Int
        var nextResetUnix: Double?
        var billingPeriod: String?

        enum CodingKeys: String, CodingKey {
            case tier, status
            case characterCount = "character_count"
            case characterLimit = "character_limit"
            case nextResetUnix = "next_character_count_reset_unix"
            case billingPeriod = "billing_period"
        }
    }

    enum ClientError: LocalizedError {
        case unauthorized(String)
        case http(Int)
        case invalidResponse
        case network(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized(let m): return m
            case .http(let c): return "Unexpected HTTP \(c)"
            case .invalidResponse: return "Invalid response from ElevenLabs"
            case .network(let m): return m
            }
        }
    }

    func subscription(key: String) async throws -> Subscription {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user/subscription")!)
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClientError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw ClientError.unauthorized(Self.detail(data) ?? "Key rejected (\(http.statusCode)).")
        }
        guard http.statusCode == 200 else { throw ClientError.http(http.statusCode) }

        do {
            return try JSONDecoder().decode(Subscription.self, from: data)
        } catch {
            throw ClientError.invalidResponse
        }
    }

    /// ElevenLabs nests the human-readable reason under `detail.message`.
    /// The common one is "missing the permission user_read".
    private static func detail(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = obj["detail"] as? [String: Any],
              let message = detail["message"] as? String else {
            return nil
        }
        if message.contains("user_read") {
            return "This key lacks the user_read permission. Edit it in the ElevenLabs dashboard → API Keys → enable User: Read."
        }
        return message
    }
}
