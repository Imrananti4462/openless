import Foundation

public enum CapsuleState: Sendable, Equatable {
    case hidden
    case listening
    case processing
    case inserted
    case cancelled
    case copied
    case error(String)
}
