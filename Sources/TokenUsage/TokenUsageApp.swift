import SwiftUI
import AppKit
import Combine
import UserNotifications
import Carbon

@main
struct TokenUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var service = UsageService()
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if UsageService.notificationsSupported {
            UNUserNotificationCenter.current().delegate = self
            service.requestNotificationPermission()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.action = #selector(togglePopover)
            button.target = self
            updateStatusButton()
        }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 340, height: 480)
        pop.contentViewController = NSHostingController(
            rootView: PopoverView(service: service, onQuit: { [weak self] in
                self?.popover?.performClose(nil)
                NSApp.terminate(nil)
            })
        )
        popover = pop

        service.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateStatusButton()
            }
            .store(in: &cancellables)

        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateStatusButton()
            }
        }

        // ⌥E — works system-wide while the menu bar app is running.
        hotKey = HotKey(keyCode: kVK_ANSI_E, modifiers: optionKey) { [weak self] in
            self?.togglePopover()
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(togglePopover),
            name: Notification.Name("com.tokenusage.app.toggle"),
            object: nil
        )
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "tokenusage" {
            // tokenusage://toggle  |  tokenusage://show
            let action = (url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).lowercased()
            if action == "toggle" || action.isEmpty {
                togglePopover()
            } else if action == "show" {
                showPopover()
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    @objc func togglePopover() {
        guard let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown { return }

        Task { await service.refresh(forceFable: false) }
        // Activate so the popover receives key events / stays above.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let view = popover.contentViewController?.view {
            let fitting = view.fittingSize
            popover.contentSize = NSSize(width: 340, height: max(300, min(600, fitting.height)))
        }
        removeMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeMonitor()
    }

    private func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }

        if !service.isConfigured {
            button.attributedTitle = NSAttributedString(
                string: "TU",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                    .foregroundColor: NSColor.labelColor
                ]
            )
            button.toolTip = "TokenUsage — ⌥E to open"
            return
        }

        let remaining = service.snapshot.menuBarRemaining
        let level = service.snapshot.primaryLevel
        let text: String
        if let remaining {
            text = "\(remaining)%"
        } else if service.snapshot.error != nil {
            text = "!"
        } else {
            text = "…"
        }

        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold),
            .foregroundColor: level.menuBarColor
        ])
        button.toolTip = tooltip() + " · ⌥E"
    }

    private func tooltip() -> String {
        var parts: [String] = []
        if let s = service.snapshot.session {
            parts.append("5h: \(s.remainingLabel)")
        }
        if let w = service.snapshot.weekly {
            parts.append("Weekly: \(w.remainingLabel)")
        }
        if let f = service.snapshot.fable {
            parts.append("Fable: \(f.remainingLabel)")
        }
        if let c = service.snapshot.context {
            parts.append("This chat: \(c.remainingPercentLabel)")
        }
        return parts.isEmpty ? "TokenUsage" : parts.joined(separator: " · ")
    }
}
