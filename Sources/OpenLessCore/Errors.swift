import Foundation

public enum DictationError: Error, Sendable, Equatable {
    case microphonePermissionMissing
    case accessibilityMissing
    case credentialsMissing
    case asrFailed(String)
    case polishFailed(String)
    case insertionFailed(String)
    case networkUnavailable
}
