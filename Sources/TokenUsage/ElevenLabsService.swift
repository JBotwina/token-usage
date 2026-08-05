import Foundation

/// Polls the ElevenLabs character quota. Slower cadence than Claude — the
/// counter only moves when you synthesise, and the limit resets monthly.
@MainActor
final class ElevenLabsService: ObservableObject {
    @Published private(set) var snapshot = ElevenLabsSnapshot()
    @Published private(set) var isConfigured: Bool
    @Published private(set) var isRefreshing = false
    @Published var setupError: String?

    private let client = ElevenLabsClient()
    private var pollTask: Task<Void, Never>?
    private let pollInterval: TimeInterval = 5 * 60

    init() {
        self.isConfigured = ElevenLabsKeyStore.hasKey
        if isConfigured { startPolling() }
    }

    // MARK: - Setup

    func saveKey(_ raw: String) async {
        setupError = nil
        let key = raw.filter { !$0.isWhitespace }
        guard !key.isEmpty else {
            setupError = "Paste an ElevenLabs API key (sk_…)."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            _ = try await client.subscription(key: key)
            try ElevenLabsKeyStore.save(key)
            isConfigured = true
            await refresh()
            startPolling()
        } catch {
            setupError = error.localizedDescription
        }
    }

    func clearKey() {
        pollTask?.cancel()
        pollTask = nil
        ElevenLabsKeyStore.delete()
        isConfigured = false
        snapshot = ElevenLabsSnapshot()
        setupError = nil
    }

    // MARK: - Polling

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 300) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func refresh() async {
        guard let key = ElevenLabsKeyStore.load() else {
            isConfigured = false
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let sub = try await client.subscription(key: key)
            snapshot = ElevenLabsSnapshot(
                tier: sub.tier,
                used: sub.characterCount,
                limit: sub.characterLimit,
                resetAt: sub.nextResetUnix.map { Date(timeIntervalSince1970: $0) },
                lastPolled: Date(),
                error: nil
            )
        } catch {
            snapshot.lastPolled = Date()
            snapshot.error = error.localizedDescription
        }
    }
}
