import AppKit
import SwiftUI
import TunnelManServer

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let sessionManager = SessionManager()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "TunnelMan")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.contentSize = NSSize(width: 340, height: 460)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(sessionManager: sessionManager)
        )
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit TunnelMan", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    func updateIcon(state: TunnelState) {
        let symbolName: String
        switch state {
        case .idle:              symbolName = "terminal"
        case .starting:          symbolName = "terminal.fill"
        case .connected:         symbolName = "network"
        case .error:             symbolName = "exclamationmark.triangle"
        case .needsDevTunnelLogin: symbolName = "person.badge.key"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "TunnelMan")
        image?.isTemplate = true
        statusItem.button?.image = image
    }
}
