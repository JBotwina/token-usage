import SwiftUI
import AppKit

enum Theme {
    /// Resolves per-appearance, so the popover follows the system light/dark setting.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    private static func srgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    // warm cream ⇄ warm charcoal
    static let bg = dynamic(light: srgb(0.98, 0.96, 0.93), dark: srgb(0.12, 0.11, 0.11))
    static let card = dynamic(light: srgb(1, 1, 1, 0.92), dark: srgb(1, 1, 1, 0.06))
    /// Text-field / input background.
    static let field = dynamic(light: srgb(1, 1, 1), dark: srgb(1, 1, 1, 0.07))
    /// Inline code chip.
    static let chip = dynamic(light: srgb(0, 0, 0, 0.05), dark: srgb(1, 1, 1, 0.09))

    static let text = dynamic(light: srgb(0.18, 0.16, 0.14), dark: srgb(0.93, 0.91, 0.88))
    static let muted = dynamic(light: srgb(0.45, 0.42, 0.38), dark: srgb(0.63, 0.60, 0.56))
    static let hairline = dynamic(light: srgb(0, 0, 0, 0.08), dark: srgb(1, 1, 1, 0.10))

    // terracotta (CTA) — lifted in dark so it stays legible on charcoal
    static let accent = dynamic(light: srgb(0.78, 0.42, 0.28), dark: srgb(0.89, 0.53, 0.37))
    static let barTrack = dynamic(light: srgb(0, 0, 0, 0.06), dark: srgb(1, 1, 1, 0.12))

    static func barFill(usedPercent: Double) -> Color {
        let remaining = 100 - usedPercent
        return AlertLevel.from(remainingPercent: remaining).accent
    }
}

// MARK: - Progress bar

struct UsageBar: View {
    let usedPercent: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.barTrack)
                Capsule()
                    .fill(Theme.barFill(usedPercent: usedPercent))
                    .frame(width: max(4, geo.size.width * CGFloat(min(1, usedPercent / 100))))
            }
        }
        .frame(height: height)
    }
}
