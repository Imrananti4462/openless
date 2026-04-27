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

    @discardableResult
    public func learnTerms(from text: String) -> [DictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }

        var entries = loadAll()
        let existing = Set(entries.map { $0.trimmedPhrase.lowercased() })
        let candidates = Self.extractLearnableTerms(from: text)
            .filter { !existing.contains($0.lowercased()) }
            .prefix(8)

        let learned = candidates.map {
            DictionaryEntry(
                phrase: $0,
                category: .learned,
                notes: "自动从历史输入中学习，可作为后续 ASR 热词和语义判断候选。",
                enabled: true,
                source: .automatic
            )
        }
        if !learned.isEmpty {
            entries.insert(contentsOf: learned, at: 0)
            saveLocked(entries)
        }
        return Array(learned)
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

    private static func extractLearnableTerms(from text: String) -> [String] {
        let pattern = #"[A-Za-z][A-Za-z0-9_.+#-]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        let stopwords: Set<String> = [
            "and", "the", "for", "with", "from", "this", "that", "you", "your",
            "http", "https", "www", "com", "app", "api", "json", "true", "false"
        ]

        var result: [String] = []
        var seen = Set<String>()
        for match in matches {
            guard let tokenRange = Range(match.range, in: text) else { continue }
            let token = String(text[tokenRange])
            let lower = token.lowercased()
            let hasSignal = token.contains { $0.isUppercase } || token.contains { $0.isNumber } || token.contains(".") || token.contains("+") || token.contains("#")
            guard hasSignal, !stopwords.contains(lower), seen.insert(lower).inserted else { continue }
            result.append(token)
        }
        return result
    }
}
