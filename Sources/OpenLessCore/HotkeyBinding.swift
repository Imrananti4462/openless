import Foundation

public struct HotkeyBinding: Codable, Sendable, Equatable {
    public enum Trigger: String, Codable, Sendable, Equatable, CaseIterable {
        case rightOption
        case leftOption
        case rightCommand
        case rightControl
        case leftControl
        case fn

        public var displayName: String {
            switch self {
            case .rightOption: return "右 Option"
            case .leftOption: return "左 Option"
            case .rightCommand: return "右 Command"
            case .rightControl: return "右 Control"
            case .leftControl: return "左 Control"
            case .fn: return "Fn / 🌐"
            }
        }
    }

    public let trigger: Trigger

    public init(trigger: Trigger) {
        self.trigger = trigger
    }

    public static let `default` = HotkeyBinding(trigger: .rightOption)
}
