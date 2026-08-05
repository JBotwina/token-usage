import Foundation

/// Aggregates today's message and token counts across all Claude Code session
/// transcripts under `~/.claude/projects/`.
enum ContextReader {
    private static let projectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

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
                tokens += usage
            }
        }
        return TodayStats(messages: messages, tokens: tokens)
    }

    // MARK: - Internals

    private static func allTranscripts() -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var urls: [URL] = []
        for case let url as URL in enumerator {
            // Skip subagent transcripts — their usage is already billed to the parent
            if url.path.contains("/subagents/") { continue }
            if url.pathExtension == "jsonl" {
                urls.append(url)
            }
        }
        return urls
    }

    private static func extractUsage(from line: String) -> Int? {
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
        let total = input + cacheCreate + cacheRead
        return total > 0 ? total : nil
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
