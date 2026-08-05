import Foundation
import SwiftUI
import AppKit

// MARK: - Alert level (based on % remaining)

enum AlertLevel: String, CaseIterable, Identifiable {
    case normal
    case low       // < 20% remaining
    case veryLow   // < 5% remaining

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .low: return "Almost hit"
        case .veryLow: return "Limit low"
        }
    }

    /// remaining in 0…100
    static func from(remainingPercent: Double) -> AlertLevel {
        if remainingPercent < 5 { return .veryLow }
        if remainingPercent < 20 { return .low }
        return .normal
    }

    var accent: Color {
        switch self {
        case .normal:  // soft green
            return Theme.dynamic(
                light: NSColor(srgbRed: 0.35, green: 0.62, blue: 0.42, alpha: 1),
                dark: NSColor(srgbRed: 0.45, green: 0.78, blue: 0.55, alpha: 1)
            )
        case .low:     // amber
            return Theme.dynamic(
                light: NSColor(srgbRed: 0.85, green: 0.58, blue: 0.25, alpha: 1),
                dark: NSColor(srgbRed: 0.95, green: 0.71, blue: 0.36, alpha: 1)
            )
        case .veryLow: // terracotta
            return Theme.dynamic(
                light: NSColor(srgbRed: 0.72, green: 0.32, blue: 0.22, alpha: 1),
                dark: NSColor(srgbRed: 0.91, green: 0.45, blue: 0.35, alpha: 1)
            )
        }
    }

    var menuBarColor: NSColor {
        switch self {
        case .normal: return .labelColor
        case .low: return .systemOrange
        case .veryLow: return .systemRed
        }
    }
}

// MARK: - Rate-limit window

struct RateWindow: Equatable {
    /// Raw utilization from the API (may exceed 100 when over quota).
    var usedPercent: Double
    var resetAt: Date?
    var status: String?

    /// Clamped 0…100 for display / bars.
    var usedPercentClamped: Double { min(100, max(0, usedPercent)) }

    /// How much quota is left (0…100). Over-quota → 0.
    var remainingPercent: Double { max(0, 100 - usedPercentClamped) }

    var remainingLabel: String { "\(Int(remainingPercent.rounded()))% left" }

    var level: AlertLevel { .from(remainingPercent: remainingPercent) }

    var resetRelative: String {
        guard let resetAt else { return "—" }
        let interval = resetAt.timeIntervalSinceNow
        if interval <= 0 { return "soon" }
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            let remH = hours % 24
            return remH > 0 ? "\(days)d \(remH)h" : "\(days)d"
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    var resetAbsolute: String {
        guard let resetAt else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "EEE h:mm a"
        return f.string(from: resetAt)
    }
}

// MARK: - Aggregate snapshot

struct UsageSnapshot: Equatable {
    var session: RateWindow?
    var weekly: RateWindow?
    var fable: RateWindow?
    var plan: String?
    var organizationId: String?
    var lastPolled: Date?
    var error: String?

    /// Tightest remaining % across rate windows.
    var primaryRemaining: Double? {
        var rem: [Double] = []
        if let s = session { rem.append(s.remainingPercent) }
        if let w = weekly { rem.append(w.remainingPercent) }
        return rem.min()
    }

    var primaryLevel: AlertLevel {
        guard let r = primaryRemaining else { return .normal }
        return .from(remainingPercent: r)
    }

    /// Prefer session remaining for the menu bar, fall back to weekly.
    var menuBarRemaining: Int? {
        if let s = session { return Int(s.remainingPercent.rounded()) }
        if let w = weekly { return Int(w.remainingPercent.rounded()) }
        return nil
    }
}

// MARK: - ElevenLabs credits

/// ElevenLabs bills characters, not tokens, and refills on a monthly boundary.
struct ElevenLabsSnapshot: Equatable {
    var tier: String?
    var used: Int = 0
    var limit: Int = 0
    var resetAt: Date?
    var lastPolled: Date?
    var error: String?

    var remaining: Int { max(0, limit - used) }

    var usedPercent: Double {
        guard limit > 0 else { return 0 }
        return min(100, max(0, Double(used) / Double(limit) * 100))
    }

    var remainingPercent: Double { 100 - usedPercent }

    var level: AlertLevel { .from(remainingPercent: remainingPercent) }

    var remainingLabel: String { "\(Self.compact(remaining)) left" }

    var usageLabel: String { "\(Self.compact(used)) / \(Self.compact(limit))" }

    var resetRelative: String {
        guard let resetAt else { return "—" }
        let interval = resetAt.timeIntervalSinceNow
        if interval <= 0 { return "soon" }
        let days = Int(interval) / 86_400
        let hours = (Int(interval) % 86_400) / 3600
        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        let minutes = (Int(interval) % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    static func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Today stats (from local transcripts)

struct TodayStats: Equatable {
    var messages: Int
    var tokens: Int

    var tokensLabel: String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }
}
