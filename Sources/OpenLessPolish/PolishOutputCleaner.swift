import Foundation

/// 清理 LLM 返回内容里常见的"引导套话"和 markdown 代码栅栏。
///
/// 即使我们在 prompt 里明确禁止"根据您给的内容，整理如下"等开场白，仍有部分模型会顽固加上；
/// 在客户端再扫一遍确保插入到光标位置的就是干净正文。
///
/// 这是公共类型——之前藏在 DoubaoPolishClient 内部，B-3 抽成独立文件后被
/// `OpenAICompatibleLLMProvider` 复用，并保留 `PolishOutputCleanerTests` 直接测试入口。
public enum PolishOutputCleaner {
    /// 已知会被加在正文最前面的引导套话正则集合（顺序无关，循环匹配）。
    private static let leadingBoilerplatePatterns: [String] = [
        #"(?s)^根据[你您]?(?:给的|提供的)?内容[，,\s]*(?:我)?(?:已经|已)?(?:整理|优化)(?:好|完成)?(?:如下)?[：:\s]*"#,
        #"(?s)^以下(?:是|为)?(?:整理|优化|结构化整理)后?的?内容(?:如下)?[：:\s]*"#,
        #"(?s)^(?:整理|优化|结构化整理)(?:后?的?内容)?(?:如下)?[：:\s]*"#,
    ]

    public static func clean(_ content: String) -> String {
        var output = content.trimmingCharacters(in: .whitespacesAndNewlines)
        output = stripMarkdownFence(from: output)

        // 多模型可能叠加多次套话；循环到不再变化为止。
        var changed = true
        while changed {
            changed = false
            for pattern in leadingBoilerplatePatterns {
                if let range = output.range(of: pattern, options: .regularExpression),
                   range.lowerBound == output.startIndex {
                    output.removeSubrange(range)
                    output = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    changed = true
                }
            }
        }

        return output
    }

    /// 去掉首尾的 ```...``` 围栏（含语言标记行如 ```text）。
    private static func stripMarkdownFence(from text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```") else { return text }
        var lines = text.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return text }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
