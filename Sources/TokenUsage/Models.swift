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
        case .normal: return Color(red: 0.35, green: 0.62, blue: 0.42)   // soft green
        case .low: return Color(red: 0.85, green: 0.58, blue: 0.25)      // amber
        case .veryLow: return Color(red: 0.72, green: 0.32, blue: 0.22)  // terracotta
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

// MARK: - Session context (local Claude Code transcript)

struct SessionContext: Equatable {
    var usedTokens: Int
    var usableTokens: Int
    var model: String?
    var updatedAt: Date

    var remainingTokens: Int { max(0, usableTokens - usedTokens) }
    var usedPercent: Double {
        guard usableTokens > 0 else { return 0 }
        return min(100, Double(usedTokens) / Double(usableTokens) * 100)
    }
    var remainingPercent: Double { max(0, 100 - usedPercent) }
    var level: AlertLevel { .from(remainingPercent: remainingPercent) }

    var usedLabel: String { Self.compact(usedTokens) }
    /// Primary readout: remaining % of this conversation's token budget.
    var remainingPercentLabel: String { "\(Int(remainingPercent.rounded()))% left" }
    var remainingTokensLabel: String { Self.compact(remainingTokens) + " tokens" }
    var usableLabel: String { Self.compact(usableTokens) }

    private static func compact(_ n: Int) -> String {
        if n >= 1_000_000 {
            return String(format: "%.1fM", Double(n) / 1_000_000)
        }
        if n >= 1_000 {
            let k = Double(n) / 1_000
            return k >= 100 ? String(format: "%.0fK", k) : String(format: "%.1fK", k).replacingOccurrences(of: ".0K", with: "K")
        }
        return "\(n)"
    }
}

// MARK: - Aggregate snapshot

struct UsageSnapshot: Equatable {
    var session: RateWindow?
    var weekly: RateWindow?
    var fable: RateWindow?
    var context: SessionContext?
    var plan: String?
    var organizationId: String?
    var lastPolled: Date?
    var error: String?

    /// Tightest remaining % across rate windows (and context if present).
    var primaryRemaining: Double? {
        var rem: [Double] = []
        if let s = session { rem.append(s.remainingPercent) }
        if let w = weekly { rem.append(w.remainingPercent) }
        if let c = context { rem.append(c.remainingPercent) }
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
