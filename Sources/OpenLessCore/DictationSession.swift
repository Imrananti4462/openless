import Foundation

public struct DictationSession: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let rawTranscript: String
    public let finalText: String
    public let mode: PolishMode
    public let appBundleId: String?
    public let appName: String?
    public let insertStatus: InsertStatus
    public let errorCode: String?
    public let durationMs: Int?
    public let dictionaryEntryCount: Int?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawTranscript: String,
        finalText: String,
        mode: PolishMode,
        appBundleId: String?,
        appName: String?,
        insertStatus: InsertStatus,
        errorCode: String?,
        durationMs: Int? = nil,
        dictionaryEntryCount: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawTranscript = rawTranscript
        self.finalText = finalText
        self.mode = mode
        self.appBundleId = appBundleId
        self.appName = appName
        self.insertStatus = insertStatus
        self.errorCode = errorCode
        self.durationMs = durationMs
        self.dictionaryEntryCount = dictionaryEntryCount
    }
}

public enum InsertStatus: String, Codable, Sendable, Equatable {
    case inserted
    case copiedFallback
    case failed
}
