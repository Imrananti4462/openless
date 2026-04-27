import Foundation

public enum HotkeyMode: String, Codable, Sendable, Equatable, CaseIterable {
    /// 按一次开始，按一次结束。短按门槛低、适合长口述。
    case toggle
    /// 按住录音、松手即停。适合短促、连续的口播（同 Wispr Flow / Typeless 默认行为）。
    case hold

    public var displayName: String {
        switch self {
        case .toggle: return "切换式"
        case .hold: return "按住说话"
        }
    }

    public var hint: String {
        switch self {
        case .toggle: return "按一次开始录音，再按一次结束。"
        case .hold: return "按住快捷键说话，松开立即停止。适合短句。"
        }
    }
}
