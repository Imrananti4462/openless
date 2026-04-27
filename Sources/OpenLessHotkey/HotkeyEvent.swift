import Foundation

public enum HotkeyEvent: Sendable, Equatable {
    /// 触发键按下边沿。toggle 模式下解释为「开始/结束」翻转，hold 模式下解释为「开始」。
    case pressed
    /// 触发键松开边沿。toggle 模式忽略；hold 模式解释为「结束」。
    case released
    /// 录音中按 Esc。
    case cancelled
}
