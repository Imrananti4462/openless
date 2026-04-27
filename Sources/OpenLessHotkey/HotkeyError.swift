import Foundation

public enum HotkeyError: Error, Sendable, Equatable {
    case alreadyRunning
    case accessibilityNotGranted
    case eventTapCreateFailed
}
