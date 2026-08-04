import SwiftUI
import AppKit
import Combine

@main
struct TokenUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var service = UsageService()
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
            removeMonitor()
        } else {
            Task { await service.refresh(forceFable: false) }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let view = popover.contentViewController?.view {
                let fitting = view.fittingSize
                popover.contentSize = NSSize(width: 340, height: max(300, min(600, fitting.height)))
            }
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in
                    self?.popover?.performClose(nil)
                    self?.removeMonitor()
                }
            }
        }
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
            button.toolTip = "TokenUsage — paste a setup token"
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

        // Bold monospaced digits so the menu bar stays readable at a glance.
        button.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold),
            .foregroundColor: level.menuBarColor
        ])
        button.toolTip = tooltip()
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
