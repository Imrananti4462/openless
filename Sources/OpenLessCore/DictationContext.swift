import Foundation

public struct DictationContext: Sendable, Equatable {
    public let appBundleId: String?
    public let appName: String?
    public let mode: PolishMode

    public init(appBundleId: String?, appName: String?, mode: PolishMode) {
        self.appBundleId = appBundleId
        self.appName = appName
        self.mode = mode
    }
}

public struct RawTranscript: Sendable, Equatable {
    public let text: String
    public let durationMs: Int

    public init(text: String, durationMs: Int) {
        self.text = text
        self.durationMs = durationMs
    }
}

public struct FinalText: Sendable, Equatable {
    public let text: String
    public let mode: PolishMode

    public init(text: String, mode: PolishMode) {
        self.text = text
        self.mode = mode
    }
}
