import Foundation

public enum HotkeyEvent: Sendable, Equatable {
    /// Toggle 模式下：每次触发键按下时触发一次。
    case toggled
    /// 录音中按 Esc
    case cancelled
}
