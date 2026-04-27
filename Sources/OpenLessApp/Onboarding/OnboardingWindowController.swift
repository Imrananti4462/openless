import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    func show() {
        let onCompleteCopy = onComplete
        let view = OnboardingView(onComplete: onCompleteCopy)
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "OpenLess"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 480, height: 360))
        win.center()
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        self.window = win

        NSApp.setActivationPolicy(.regular)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
