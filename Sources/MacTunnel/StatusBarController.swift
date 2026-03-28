import AppKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let sessionManager = SessionManager()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "MacTunnel")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentSize = NSSize(width: 340, height: 460)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(sessionManager: sessionManager)
        )
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func updateIcon(state: TunnelState) {
        let symbolName: String
        switch state {
        case .idle:      symbolName = "terminal"
        case .starting:  symbolName = "terminal.fill"
        case .connected: symbolName = "network"
        case .error:     symbolName = "exclamationmark.triangle"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MacTunnel")
    }
}
