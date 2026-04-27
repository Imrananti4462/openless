import Foundation
import OpenLessCore

/// v1 demo 简化版历史：JSON 文件 append；后续切 SQLite。
public final class HistoryStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenLess", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("history.json")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: "[]".data(using: .utf8))
        }
    }

    public func save(_ session: DictationSession) {
        lock.lock()
        defer { lock.unlock() }
        var sessions = loadAll()
        sessions.insert(session, at: 0)
        if sessions.count > 200 { sessions = Array(sessions.prefix(200)) }
        if let data = try? encoder.encode(sessions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    public func recent(limit: Int = 50) -> [DictationSession] {
        lock.lock()
        defer { lock.unlock() }
        return Array(loadAll().prefix(limit))
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? "[]".data(using: .utf8)?.write(to: fileURL)
    }

    private func loadAll() -> [DictationSession] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([DictationSession].self, from: data)) ?? []
    }
}
