import Foundation

public enum PolishMode: String, Codable, Sendable, Equatable, CaseIterable {
    case raw
    case light
    case structured
    case formal

    public var displayName: String {
        switch self {
        case .raw: return "原文"
        case .light: return "轻度润色"
        case .structured: return "清晰结构"
        case .formal: return "正式表达"
        }
    }
}
