import Foundation
import UserNotifications

/// Owns poll state. Session/weekly every `pollInterval`, Fable slower, today often.
@MainActor
final class UsageService: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot()
    @Published private(set) var today = TodayStats(messages: 0, tokens: 0)
    @Published private(set) var isConfigured: Bool
    @Published private(set) var isRefreshing = false
    @Published var setupError: String?

    private let client = AnthropicClient()
    private var pollTask: Task<Void, Never>?
    private var lastFableProbe: Date?
    private var lastNotifiedLevel: AlertLevel = .normal

    private let pollInterval: TimeInterval = 120          // 2 min
    private let fableInterval: TimeInterval = 20 * 60     // 20 min
    private let todayInterval: TimeInterval = 15          // 15 s

    init() {
        self.isConfigured = TokenStore.hasToken
        if isConfigured {
            refreshToday()
            startPolling()
            requestNotificationPermission()
        }
    }

    /// Call once after install so macOS shows the notifications prompt.
    func requestNotificationPermission() {
        guard Self.notificationsAvailable else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    // MARK: - Setup

    func saveToken(_ raw: String) async {
        setupError = nil
        let token = raw.filter { !$0.isWhitespace }
        guard !token.isEmpty else {
            setupError = "Paste a token from `claude setup-token`."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            _ = try await client.ping(token: token)
            try TokenStore.save(token)
            isConfigured = true
            requestNotificationPermission()
            await refresh(forceFable: true)
            startPolling()
        } catch {
            setupError = error.localizedDescription
        }
    }

    /// Fire a sample notification (⋯ menu) so the user can verify permissions.
    func sendTestNotification() {
        guard Self.notificationsAvailable else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = "TokenUsage"
            content.body = "Notifications are working. You'll get an alert under 20% and 5% left."
            content.sound = .default
            let req = UNNotificationRequest(
                identifier: "tokenusage-test-\(Date().timeIntervalSince1970)",
                content: content,
                trigger: nil
            )
            try? await center.add(req)
        }
    }

    func clearToken() {
        pollTask?.cancel()
        pollTask = nil
        TokenStore.delete()
        isConfigured = false
        snapshot = UsageSnapshot()
        today = TodayStats(messages: 0, tokens: 0)
        setupError = nil
    }

    // MARK: - Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            // Immediate full refresh
            await self?.refresh(forceFable: true)
            while !Task.isCancelled {
                // Transcript scanning is cheap — tick often between full polls
                let ticks = max(1, Int((self?.pollInterval ?? 120) / (self?.todayInterval ?? 15)))
                for _ in 0..<ticks {
                    try? await Task.sleep(nanoseconds: UInt64((self?.todayInterval ?? 15) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self?.refreshToday() }
                }
                await self?.refresh(forceFable: false)
            }
        }
    }

    func refresh(forceFable: Bool = false) async {
        guard let token = TokenStore.load() else {
            isConfigured = false
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let ping = try await client.ping(token: token)
            var next = snapshot
            next.session = ping.session
            next.weekly = ping.weekly
            next.organizationId = ping.organizationId.isEmpty ? next.organizationId : ping.organizationId
            next.lastPolled = Date()
            next.error = nil

            let needFable = forceFable
                || lastFableProbe == nil
                || Date().timeIntervalSince(lastFableProbe!) >= fableInterval
                || next.fable == nil

            if needFable {
                let fable = await client.probeFable(token: token)
                if let window = fable.fable {
                    next.fable = window
                }
                // Keep previous fable reading if probe returned no 7d_oi headers
                lastFableProbe = Date()
            }

            snapshot = next
            refreshToday()
            maybeNotify(next.primaryLevel)
        } catch {
            snapshot.error = error.localizedDescription
            if let err = error as? AnthropicClient.ClientError, case .unauthorized = err {
                // Keep token; surface error so user can re-paste
            }
        }
    }

    func refreshToday() {
        today = ContextReader.todayStats()
    }

    // MARK: - Notifications

    /// UNUserNotificationCenter requires a real .app bundle with an identifier.
    /// `swift run` / bare binary under `.build/` has none and will abort the process.
    static var notificationsSupported: Bool {
        guard let id = Bundle.main.bundleIdentifier, !id.isEmpty else { return false }
        let path = Bundle.main.bundlePath
        if path.contains("/.build/") || path.hasSuffix(".build") { return false }
        return path.hasSuffix(".app") || path.contains(".app/")
    }

    private static var notificationsAvailable: Bool { notificationsSupported }

    private func maybeNotify(_ level: AlertLevel) {
        guard Self.notificationsAvailable else {
            lastNotifiedLevel = level
            return
        }
        guard level != .normal, level != lastNotifiedLevel else {
            if level == .normal { lastNotifiedLevel = .normal }
            return
        }
        // Only escalate, don't re-fire same level
        let order: [AlertLevel] = [.normal, .low, .veryLow]
        let prev = order.firstIndex(of: lastNotifiedLevel) ?? 0
        let curr = order.firstIndex(of: level) ?? 0
        guard curr > prev else {
            lastNotifiedLevel = level
            return
        }
        lastNotifiedLevel = level

        let rem = snapshot.primaryRemaining.map { Int($0.rounded()) } ?? 0
        let title = level == .veryLow ? "Limit Running Low" : "Approaching Limit"
        let body = level == .veryLow
            ? "~\(rem)% remaining. Consider starting a new session."
            : "Under 20% remaining on your tightest window."

        Task {
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                status = await center.notificationSettings().authorizationStatus
            }
            guard status == .authorized || status == .provisional else { return }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            // Stable id per level so we replace rather than stack spam.
            let req = UNNotificationRequest(
                identifier: "tokenusage-\(level.rawValue)",
                content: content,
                trigger: nil
            )
            try? await center.add(req)
        }
    }
}
