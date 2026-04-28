import Foundation
import OpenLessCore

public final class UserPreferences: @unchecked Sendable {
    public static let shared = UserPreferences()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let polishMode = "openless.polish_mode"
        static let polishEnabled = "openless.polish_enabled"
        static let hotkeyTrigger = "openless.hotkey_trigger"
        static let hotkeyMode = "openless.hotkey_mode"
        static let hasCompletedOnboarding = "openless.onboarding_completed"
    }

    public init() {}

    /// 风格全局开关。关闭时识别后直接插入原文，不调润色模型。默认开。
    public var polishEnabled: Bool {
        get {
            if defaults.object(forKey: Key.polishEnabled) == nil { return true }
            return defaults.bool(forKey: Key.polishEnabled)
        }
        set { defaults.set(newValue, forKey: Key.polishEnabled) }
    }

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

    public var hotkeyMode: HotkeyMode {
        get {
            let raw = defaults.string(forKey: Key.hotkeyMode) ?? HotkeyMode.toggle.rawValue
            return HotkeyMode(rawValue: raw) ?? .toggle
        }
        set { defaults.set(newValue.rawValue, forKey: Key.hotkeyMode) }
    }

    public var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }
}
