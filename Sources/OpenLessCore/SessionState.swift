import Foundation

public enum SessionState: Sendable, Equatable {
    case idle
    case listening
    case transcribing
    case polishing
    case inserting
    case inserted
    case copiedFallback
    case cancelled
    case failed(String)
}
