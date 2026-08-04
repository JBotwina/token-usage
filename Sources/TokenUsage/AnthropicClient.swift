import Foundation

/// Cheap Haiku ping + optional Fable probe — same approach as claude-monitor.
/// Rate limits live in response headers on both 200 and 429.
actor AnthropicClient {
    private let session: URLSession
    private let userAgent: String

    init(userAgent: String = "claude-code/2.1.221") {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.userAgent = userAgent
    }

    struct PingResult: Sendable {
        var organizationId: String
        var httpStatus: Int
        var session: RateWindow?
        var weekly: RateWindow?
        var rawHeaders: [String: String]
    }

    struct FableResult: Sendable {
        var httpStatus: Int
        var fable: RateWindow?
        var rawHeaders: [String: String]
    }

    enum ClientError: LocalizedError {
        case unauthorized
        case http(Int)
        case invalidResponse
        case network(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized: return "Token rejected (401). Run `claude setup-token` and paste a fresh one."
            case .http(let c): return "Unexpected HTTP \(c)"
            case .invalidResponse: return "Invalid response"
            case .network(let m): return m
            }
        }
    }

    // MARK: - Ping (session + weekly)

    func ping(token: String) async throws -> PingResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        applyAuth(&request, token: token)
        request.httpBody = """
        {"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"x"}]}
        """.data(using: .utf8)

        let (_, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }

        if http.statusCode == 401 { throw ClientError.unauthorized }
        guard http.statusCode == 200 || http.statusCode == 429 else {
            throw ClientError.http(http.statusCode)
        }

        let headers = Self.extractAnthropicHeaders(http.allHeaderFields)
        return PingResult(
            organizationId: headers["anthropic-organization-id"] ?? "",
            httpStatus: http.statusCode,
            session: Self.window(
                util: headers["anthropic-ratelimit-unified-5h-utilization"],
                reset: headers["anthropic-ratelimit-unified-5h-reset"],
                status: headers["anthropic-ratelimit-unified-5h-status"]
            ),
            weekly: Self.window(
                util: headers["anthropic-ratelimit-unified-7d-utilization"],
                reset: headers["anthropic-ratelimit-unified-7d-reset"],
                status: headers["anthropic-ratelimit-unified-7d-status"]
            ),
            rawHeaders: headers
        )
    }

    // MARK: - Fable probe (premium weekly allocation)

    /// Probes `claude-fable-5` so the 7d_oi (premium) headers surface.
    /// Never throws — records whatever the API returns.
    func probeFable(token: String) async -> FableResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        applyAuth(&request, token: token)
        // Premium models need the Claude Code system prompt or they mask as 429.
        request.httpBody = """
        {"model":"claude-fable-5","max_tokens":1,"system":"You are Claude Code, Anthropic's official CLI for Claude.","messages":[{"role":"user","content":"x"}]}
        """.data(using: .utf8)

        do {
            let (_, response) = try await data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return FableResult(httpStatus: 0, fable: nil, rawHeaders: [:])
            }
            let headers = Self.extractAnthropicHeaders(http.allHeaderFields)
            let fable = Self.window(
                util: headers["anthropic-ratelimit-unified-7d_oi-utilization"],
                reset: headers["anthropic-ratelimit-unified-7d_oi-reset"],
                status: headers["anthropic-ratelimit-unified-7d_oi-status"]
            )
            return FableResult(httpStatus: http.statusCode, fable: fable, rawHeaders: headers)
        } catch {
            return FableResult(httpStatus: 0, fable: nil, rawHeaders: [:])
        }
    }

    // MARK: - Helpers

    private func applyAuth(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw ClientError.network(error.localizedDescription)
        }
    }

    static func extractAnthropicHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in headers {
            guard let key = (k as? String)?.lowercased(), key.hasPrefix("anthropic-") else { continue }
            out[key] = "\(v)"
        }
        return out
    }

    static func window(util: String?, reset: String?, status: String?) -> RateWindow? {
        guard let util, let used = Double(util) else { return nil }
        let resetDate: Date? = reset.flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) }
        return RateWindow(usedPercent: used * 100, resetAt: resetDate, status: status)
    }
}
