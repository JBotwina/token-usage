import SwiftUI

struct PopoverView: View {
    @ObservedObject var service: UsageService
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !service.isConfigured {
                SetupView(service: service)
            } else {
                UsagePanel(service: service, onQuit: onQuit)
            }
        }
        .frame(width: 340)
        .background(Theme.bg)
    }
}

// MARK: - Setup

struct SetupView: View {
    @ObservedObject var service: UsageService
    @State private var token = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("TokenUsage")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            Text("Track Claude Code limits from your menu bar.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. In Terminal, run:")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                HStack {
                    Text("claude setup-token")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("claude setup-token", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
                    .help("Copy command")
                }
                Text("2. Paste the token below (sk-ant-oat01-…)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
            }

            SecureField("Paste token…", text: $token)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let err = service.setupError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await service.saveToken(token) }
            } label: {
                HStack {
                    if service.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                    Text(service.isRefreshing ? "Verifying…" : "Save token")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(token.filter { !$0.isWhitespace }.isEmpty || service.isRefreshing)

            Text("Token stays in your Keychain. Never leaves this Mac except to call Anthropic.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
    }
}

// MARK: - Usage panel

struct UsagePanel: View {
    @ObservedObject var service: UsageService
    var onQuit: () -> Void

    private var snap: UsageSnapshot { service.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: 16) {
                if let session = snap.session {
                    windowRow(
                        icon: "clock",
                        title: "5-hour window",
                        window: session,
                        subtitle: "Resets in \(session.resetRelative)"
                    )
                }

                if let weekly = snap.weekly {
                    windowRow(
                        icon: "calendar",
                        title: "Weekly",
                        window: weekly,
                        subtitle: "Resets \(weekly.resetAbsolute)"
                    )
                }

                if let fable = snap.fable {
                    windowRow(
                        icon: "sparkles",
                        title: "Fable",
                        window: fable,
                        subtitle: fable.resetAt != nil ? "Resets \(fable.resetAbsolute)" : "Premium model allocation"
                    )
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fable")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.text)
                            Text("Probing… or not on plan")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text("—")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.muted)
                    }
                }

                if let ctx = snap.context {
                    chatMemoryRow(ctx)
                }

                todayRow

                if let err = snap.error {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)

            Divider().overlay(Theme.hairline)

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Usage")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            if let plan = snap.plan {
                Text(plan.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.15))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
            levelChip(snap.primaryLevel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func levelChip(_ level: AlertLevel) -> some View {
        Text(level.label)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(level.accent.opacity(0.15))
            .foregroundStyle(level.accent)
            .clipShape(Capsule())
    }

    private func windowRow(icon: String, title: String, window: RateWindow, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(window.remainingLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(window.level.accent)
            }
            // Bar still fills with *used* so empty = full headroom.
            UsageBar(usedPercent: window.usedPercentClamped, height: 7)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 26)
        }
    }

    /// Current Claude Code conversation token budget — not a rate limit.
    private func chatMemoryRow(_ ctx: SessionContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)
                Text("This chat")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(ctx.remainingPercentLabel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(ctx.level.accent)
            }
            UsageBar(usedPercent: ctx.usedPercent, height: 7)
            Text("Conversation memory · \(ctx.remainingTokensLabel) free of \(ctx.usableLabel)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .padding(.leading, 26)
        }
    }

    private var todayRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)
                Text("Today")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
            HStack {
                Text("Messages")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text("\(service.today.messages)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .padding(.leading, 26)
            HStack {
                Text("Tokens")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(service.today.tokensLabel)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .padding(.leading, 26)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(lastUpdatedLabel)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button {
                Task { await service.refresh(forceFable: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .help("Refresh now")
            .disabled(service.isRefreshing)

            Menu {
                Button("Test notification") {
                    service.sendTestNotification()
                }
                Button("Replace token…") {
                    service.clearToken()
                }
                Divider()
                Button("Quit TokenUsage", action: onQuit)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var lastUpdatedLabel: String {
        guard let d = snap.lastPolled else { return "Not yet polled" }
        let s = Int(Date().timeIntervalSince(d))
        if s < 5 { return "Updated just now" }
        if s < 60 { return "Updated \(s)s ago" }
        return "Updated \(s / 60)m ago"
    }
}
