import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let navigation = SettingsNavigationModel()

    func show(tab: OpenLessMainTab = .home) {
        NSApp.setActivationPolicy(.regular)
        navigation.selection = tab
        if let window = window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            alignTrafficLights(in: window)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView(navigation: navigation))
        let win = NSWindow(contentViewController: hosting)
        win.title = "OpenLess"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.toolbar = nil
        win.isMovableByWindowBackground = true
        win.setContentSize(NSSize(width: 1040, height: 700))
        win.contentMinSize = NSSize(width: 960, height: 640)
        win.tabbingMode = .disallowed
        win.center()
        win.isReleasedWhenClosed = false
        win.delegate = self
        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self, weak win] in
            guard let win else { return }
            self?.alignTrafficLights(in: win)
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        alignTrafficLights(in: window)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        alignTrafficLights(in: window)
    }

    private func alignTrafficLights(in window: NSWindow) {
        let buttons: [NSButton?] = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton),
        ]
        for (index, button) in buttons.compactMap({ $0 }).enumerated() {
            var frame = button.frame
            frame.origin.x = 34 + CGFloat(index) * 24
            if let superview = button.superview, superview.bounds.height > 80 {
                frame.origin.y = superview.bounds.height - 38
            }
            button.frame = frame
        }
    }
}
