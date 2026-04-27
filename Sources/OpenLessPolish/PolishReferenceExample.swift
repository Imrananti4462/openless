import Foundation
import OpenLessCore

public struct PolishReferenceExample: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let mode: PolishMode
    public let raw: String
    public let polished: String
    public let tags: [String]
    public let notes: String?

    public init(
        id: String,
        mode: PolishMode,
        raw: String,
        polished: String,
        tags: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.mode = mode
        self.raw = raw
        self.polished = polished
        self.tags = tags
        self.notes = notes
    }
}

public enum PolishReferenceFormatter {
    public static func promptSection(for examples: [PolishReferenceExample]) -> String {
        let usable = examples.filter { !$0.raw.isEmpty && !$0.polished.isEmpty }.prefix(3)
        guard !usable.isEmpty else { return "" }

        let body = usable.enumerated().map { index, example in
            let tags = example.tags.isEmpty ? "" : "\n标签：\(example.tags.joined(separator: "、"))"
            let notes = example.notes.map { "\n规律：\($0)" } ?? ""
            return """
            样例 \(index + 1)：
            原始：\(sanitize(example.raw))
            整理：\(sanitize(example.polished))\(tags)\(notes)
            """
        }.joined(separator: "\n\n")

        return """
        参考改写样例：
        这些样例只用于学习“如何整理表达”的规律，不能复制样例内容，不能继承样例事实，不能把样例当作当前用户上下文。

        \(body)
        """
    }

    private static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<raw_transcript>", with: "<raw transcript>")
            .replacingOccurrences(of: "</raw_transcript>", with: "</raw transcript>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
