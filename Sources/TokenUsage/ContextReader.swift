import Foundation

/// Reads the most recently active Claude Code session transcript under
/// `~/.claude/projects/` and estimates context fill from the latest assistant
/// usage block: `input + cache_creation + cache_read`.
enum ContextReader {
    private static let defaultUsable = 200_000
    private static let projectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    static func latestContext() -> SessionContext? {
        guard let file = mostRecentTranscript() else { return nil }
        return parseContext(from: file)
    }

    static func todayStats() -> TodayStats {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        var messages = 0
        var tokens = 0

        for file in allTranscripts() {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
                  let mod = attrs[.modificationDate] as? Date,
                  mod >= start else { continue }

            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            // Tail-scan last ~256KB for today's assistant usages
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size > 256_000 {
                try? handle.seek(toOffset: UInt64(size - 256_000))
            }
            guard let data = try? handle.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else { continue }

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard line.contains("\"type\":\"assistant\""),
                      let usage = extractUsage(from: String(line)) else { continue }
                // Only count if timestamp is today
                if let ts = extractTimestamp(from: String(line)), ts < start { continue }
                messages += 1
                tokens += usage.total
            }
        }
        return TodayStats(messages: messages, tokens: tokens)
    }

    // MARK: - Internals

    private static func mostRecentTranscript() -> URL? {
        allTranscripts()
            .compactMap { url -> (URL, Date)? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let mod = attrs[.modificationDate] as? Date else { return nil }
                return (url, mod)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    private static func allTranscripts() -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            // Skip subagent transcripts — parent session is the context that matters
            if url.path.contains("/subagents/") { continue }
            if url.pathExtension == "jsonl" {
                urls.append(url)
            }
        }
        return urls
    }

    private static func parseContext(from file: URL) -> SessionContext? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }

        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        // Read last ~512KB — enough to cover recent turns
        if size > 512_000 {
            try? handle.seek(toOffset: UInt64(size - 512_000))
        }
        guard let data = try? handle.readToEnd(),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var lastUsage: (total: Int, model: String?)?
        var lastTs = Date.distantPast

        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            let s = String(line)
            guard s.contains("\"type\":\"assistant\"") else { continue }
            guard let usage = extractUsage(from: s) else { continue }
            let ts = extractTimestamp(from: s) ?? Date.distantPast
            lastUsage = usage
            lastTs = ts
            break
        }

        guard let lastUsage else { return nil }
        let usable = defaultUsable
        return SessionContext(
            usedTokens: lastUsage.total,
            usableTokens: usable,
            model: lastUsage.model,
            updatedAt: lastTs == Date.distantPast ? Date() : lastTs
        )
    }

    private static func extractUsage(from line: String) -> (total: Int, model: String?)? {
        // Fast path: locate "usage":{...} via JSONSerialization on the whole line
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let message = obj["message"] as? [String: Any]
        let usage = (message?["usage"] as? [String: Any]) ?? (obj["usage"] as? [String: Any])
        guard let usage else { return nil }

        let input = usage["input_tokens"] as? Int ?? 0
        let cacheCreate = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        // Context fill ≈ everything that sits in the prompt window
        let total = input + cacheCreate + cacheRead
        guard total > 0 else { return nil }

        let model = message?["model"] as? String
        return (total, model)
    }

    private static func extractTimestamp(from line: String) -> Date? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = obj["timestamp"] as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: ts) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: ts)
    }
}
