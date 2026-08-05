import SwiftUI

enum ProviderTab: String, CaseIterable, Identifiable {
    case claude
    case elevenLabs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .elevenLabs: return "ElevenLabs"
        }
    }
}

struct PopoverView: View {
    @ObservedObject var service: UsageService
    @ObservedObject var eleven: ElevenLabsService
    var onQuit: () -> Void

    @State private var tab: ProviderTab = .claude
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            TabBar(tab: $tab, showSettings: $showSettings)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 10)

            Divider().overlay(Theme.hairline)

            if showSettings {
                SettingsPanel(service: service, eleven: eleven, onQuit: onQuit)
            } else {
                switch tab {
                case .claude:
                    if !service.isConfigured {
                        SetupView(service: service)
                    } else {
                        UsagePanel(service: service, onQuit: onQuit)
                    }
                case .elevenLabs:
                    if !eleven.isConfigured {
                        ElevenLabsSetupView(service: eleven)
                    } else {
                        ElevenLabsPanel(service: eleven, onQuit: onQuit)
                    }
                }
            }
        }
        .frame(width: 340)
        .background(Theme.bg)
    }
}

// MARK: - Tab bar

/// Hand-rolled segmented control — the stock `.segmented` picker ignores the
/// theme and fights the popover background in dark mode.
struct TabBar: View {
    @Binding var tab: ProviderTab
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ProviderTab.allCases) { t in
                let selected = !showSettings && tab == t
                Button {
                    tab = t
                    showSettings = false
                } label: {
                    Text(t.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Theme.accent : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selected ? Theme.accent.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(showSettings ? Theme.accent : Theme.muted)
                    .frame(width: 30)
                    .padding(.vertical, 6)
                    .background(showSettings ? Theme.accent.opacity(0.16) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(3)
        .background(Theme.chip)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Settings

struct SettingsPanel: View {
    @ObservedObject var service: UsageService
    @ObservedObject var eleven: ElevenLabsService
    var onQuit: () -> Void

    @State private var claudeToken = ""
    @State private var elevenKey = ""
    @State private var storedClaude: String?
    @State private var storedEleven: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)

            keyField(
                title: "Claude token",
                hint: "From `claude setup-token` (sk-ant-oat01-…)",
                stored: storedClaude,
                text: $claudeToken,
                busy: service.isRefreshing,
                error: service.setupError,
                save: { await service.saveToken(claudeToken); claudeToken = ""; reload() },
                clear: { service.clearToken(); reload() }
            )

            Divider().overlay(Theme.hairline)

            keyField(
                title: "ElevenLabs key",
                hint: "Needs the User: Read permission (sk_…)",
                stored: storedEleven,
                text: $elevenKey,
                busy: eleven.isRefreshing,
                error: eleven.setupError,
                save: { await eleven.saveKey(elevenKey); elevenKey = ""; reload() },
                clear: { eleven.clearKey(); reload() }
            )

            Divider().overlay(Theme.hairline)

            HStack {
                Button("Test notification") { service.sendTestNotification() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
                Spacer()
                Button("Quit TokenUsage", action: onQuit)
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }

            Text("Both secrets live in ~/Library/Application Support/TokenUsage, mode 0600.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .onAppear(perform: reload)
    }

    private func reload() {
        storedClaude = TokenStore.load()
        storedEleven = ElevenLabsKeyStore.load()
    }

    @ViewBuilder
    private func keyField(
        title: String,
        hint: String,
        stored: String?,
        text: Binding<String>,
        busy: Bool,
        error: String?,
        save: @escaping () async -> Void,
        clear: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                if let stored {
                    Text(Self.mask(stored))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    Button("Clear", action: clear)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red.opacity(0.8))
                } else {
                    Text("Not set")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
            }

            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)

            HStack(spacing: 8) {
                SecureField(stored == nil ? "Paste…" : "Paste to replace…", text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(8)
                    .background(Theme.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    Task { await save() }
                } label: {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .buttonStyle(.plain)
                .disabled(text.wrappedValue.filter { !$0.isWhitespace }.isEmpty || busy)
            }

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func mask(_ secret: String) -> String {
        guard secret.count > 8 else { return "••••" }
        return "\(secret.prefix(5))…\(secret.suffix(4))"
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
                        .background(Theme.chip)
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
                .background(Theme.field)
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

            Text("Token stays on this Mac only (Application Support). Used solely to call Anthropic.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
    }
}

// MARK: - ElevenLabs setup

struct ElevenLabsSetupView: View {
    @ObservedObject var service: ElevenLabsService
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("ElevenLabs")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
            }

            Text("Track your monthly character credits.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("1. elevenlabs.io → Profile → API Keys")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text("2. Edit the key and enable **User: Read** — without `user_read` the quota endpoint returns 401.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text("3. Paste it below (sk_…)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
            }

            SecureField("Paste API key…", text: $key)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(Theme.field)
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
                Task { await service.saveKey(key) }
            } label: {
                HStack {
                    if service.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                    Text(service.isRefreshing ? "Verifying…" : "Save key")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(key.filter { !$0.isWhitespace }.isEmpty || service.isRefreshing)

            Text("Key stays on this Mac only (Application Support). Used solely to call ElevenLabs.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(18)
    }
}

// MARK: - ElevenLabs panel

struct ElevenLabsPanel: View {
    @ObservedObject var service: ElevenLabsService
    var onQuit: () -> Void

    private var snap: ElevenLabsSnapshot { service.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Theme.hairline)

            VStack(alignment: .leading, spacing: 16) {
                creditsRow

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
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Credits")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer()
            if let tier = snap.tier {
                Text(tier.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.15))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
            Text(snap.level.label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(snap.level.accent.opacity(0.15))
                .foregroundStyle(snap.level.accent)
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var creditsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "textformat.abc")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18)
                Text("Characters")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(snap.limit > 0 ? snap.remainingLabel : "—")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(snap.level.accent)
            }
            UsageBar(usedPercent: snap.usedPercent, height: 7)
            HStack {
                Text(snap.limit > 0 ? snap.usageLabel : "No data yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if snap.resetAt != nil {
                    Text("Resets in \(snap.resetRelative)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
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
                Task { await service.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
            .help("Refresh now")
            .disabled(service.isRefreshing)

            Menu {
                Button("Replace key…") {
                    service.clearKey()
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
