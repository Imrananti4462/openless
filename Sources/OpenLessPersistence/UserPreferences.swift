import Foundation
import OpenLessCore

public final class UserPreferences: @unchecked Sendable {
    public static let shared = UserPreferences()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let polishMode = "openless.polish_mode"
        static let hotkeyTrigger = "openless.hotkey_trigger"
        static let hasCompletedOnboarding = "openless.onboarding_completed"
    }

    public init() {}

    public var polishMode: PolishMode {
        get {
            let raw = defaults.string(forKey: Key.polishMode) ?? PolishMode.light.rawValue
            return PolishMode(rawValue: raw) ?? .light
        }
        set { defaults.set(newValue.rawValue, forKey: Key.polishMode) }
    }

    public var hotkeyTrigger: HotkeyBinding.Trigger {
        get {
            let raw = defaults.string(forKey: Key.hotkeyTrigger) ?? HotkeyBinding.Trigger.rightOption.rawValue
            return HotkeyBinding.Trigger(rawValue: raw) ?? .rightOption
        }
        set { defaults.set(newValue.rawValue, forKey: Key.hotkeyTrigger) }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }
}
