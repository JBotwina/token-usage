import SwiftUI

enum Theme {
    static let bg = Color(red: 0.98, green: 0.96, blue: 0.93)           // warm cream
    static let card = Color.white.opacity(0.92)
    static let text = Color(red: 0.18, green: 0.16, blue: 0.14)
    static let muted = Color(red: 0.45, green: 0.42, blue: 0.38)
    static let hairline = Color.black.opacity(0.08)
    static let accent = Color(red: 0.78, green: 0.42, blue: 0.28)        // terracotta (CTA)
    static let barTrack = Color.black.opacity(0.06)

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
