import Foundation
import OpenLessCore

public final class DictionaryStore: @unchecked Sendable {
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
        self.fileURL = dir.appendingPathComponent("dictionary.json")
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: "[]".data(using: .utf8))
        }
    }

    public func all() -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return loadAll()
    }

    public func enabledEntries() -> [DictionaryEntry] {
        all().filter { $0.enabled && !$0.trimmedPhrase.isEmpty }
    }

    public func upsert(_ entry: DictionaryEntry) {
        lock.lock()
        defer { lock.unlock() }
        var entries = loadAll()
        var updated = entry
        updated.phrase = updated.trimmedPhrase
        updated.updatedAt = Date()
        if let index = entries.firstIndex(where: { $0.id == updated.id }) {
            entries[index] = updated
        } else {
            entries.insert(updated, at: 0)
        }
        saveLocked(entries)
    }

    public func delete(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        let entries = loadAll().filter { $0.id != id }
        saveLocked(entries)
    }

    /// 扫描润色后文本：每个启用词条只要在文本里出现就 +1（同一次输出最多 +1）。
    /// 返回这次新增命中的 phrase，方便日志。
    @discardableResult
    public func incrementHits(matching text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        lock.lock()
        defer { lock.unlock() }

        var entries = loadAll()
        let lowerText = trimmed.lowercased()
        var hit: [String] = []
        for index in entries.indices {
            guard entries[index].enabled else { continue }
            let phrase = entries[index].trimmedPhrase
            guard !phrase.isEmpty else { continue }
            if lowerText.contains(phrase.lowercased()) {
                entries[index].hitCount += 1
                hit.append(phrase)
            }
        }
        if !hit.isEmpty {
            saveLocked(entries)
        }
        return hit
    }

    public func resetHits() {
        lock.lock()
        defer { lock.unlock() }
        var entries = loadAll()
        for index in entries.indices {
            entries[index].hitCount = 0
        }
        saveLocked(entries)
    }

    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        saveLocked([])
    }

    private func loadAll() -> [DictionaryEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([DictionaryEntry].self, from: data)) ?? []
    }

    private func saveLocked(_ entries: [DictionaryEntry]) {
        let sorted = entries.sorted { lhs, rhs in
            if lhs.enabled != rhs.enabled { return lhs.enabled && !rhs.enabled }
            return lhs.updatedAt > rhs.updatedAt
        }
        if let data = try? encoder.encode(sorted) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
