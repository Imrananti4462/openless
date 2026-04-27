import Foundation
import OpenLessCore

public enum PolishError: Error, Sendable {
    case credentialsMissing
    case requestFailed(String)
    case decodeFailed
    case modelReturnedEmpty
}

public final class DoubaoPolishClient: @unchecked Sendable {
    private let credentials: ArkCredentials
    private let logger: (@Sendable (String) -> Void)?
    private let session: URLSession

    public init(
        credentials: ArkCredentials,
        logger: (@Sendable (String) -> Void)? = nil,
        session: URLSession = .shared
    ) {
        self.credentials = credentials
        self.logger = logger
        self.session = session
    }

    public func polish(
        rawTranscript: RawTranscript,
        mode: PolishMode,
        referenceExamples: [PolishReferenceExample] = [],
        dictionaryEntries: [DictionaryEntry] = []
    ) async throws -> FinalText {
        guard !rawTranscript.text.isEmpty else {
            return FinalText(text: "", mode: mode)
        }

        var request = URLRequest(url: Self.chatCompletionsURL(from: credentials.endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization")
        // 之前 30s 太短：DeepSeek V3.2 / R1 等模型即使关思考首 token 也可能 5-10s。
        // 改成 10 分钟，等同"无上限"——polish 本身一定不会真挂这么久。
        request.timeoutInterval = 600

        let body: [String: Any] = [
            "model": credentials.modelId,
            "stream": false,
            "temperature": 0.3,
            // 关掉深度思考：V3.2 / R1 / Doubao Thinking 等模型默认会先生成一段"思考过程"
            // 再给最终答案，对"整理一段口语"这种短任务是浪费——延迟 + 成本都翻几倍。
            // 不支持 thinking 字段的模型（如 Doubao 普通版）会忽略这个参数。
            "thinking": ["type": "disabled"],
            "messages": [
                ["role": "system", "content": PolishPrompts.systemPrompt(for: mode)],
                ["role": "user", "content": PolishPrompts.userPrompt(
                    for: rawTranscript.text,
                    referenceExamples: referenceExamples,
                    dictionaryEntries: dictionaryEntries
                )],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if let httpBody = request.httpBody, let bodyStr = String(data: httpBody, encoding: .utf8) {
            logger?("[polish] request body: \(bodyStr.prefix(500))")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PolishError.requestFailed("not http")
        }
        let respPreview = String(data: data, encoding: .utf8) ?? "<no body>"
        logger?("[polish] HTTP \(http.statusCode) response: \(respPreview.prefix(500))")
        guard (200..<300).contains(http.statusCode) else {
            throw PolishError.requestFailed("HTTP \(http.statusCode): \(respPreview.prefix(300))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PolishError.decodeFailed
        }
        let trimmed = PolishOutputCleaner.clean(content)
        guard !trimmed.isEmpty else { throw PolishError.modelReturnedEmpty }
        return FinalText(text: trimmed, mode: mode)
    }

    /// Coding Plan 文档给的是 base URL `https://ark.cn-beijing.volces.com/api/coding/v3`，
    /// OpenAI SDK 会自动追加 `/chat/completions`。我们裸 URLRequest 得手动补。
    /// 用户已经填好完整 URL（含 /chat/completions）时不重复追加。
    static func chatCompletionsURL(from endpoint: URL) -> URL {
        let s = endpoint.absoluteString
        if s.hasSuffix("/chat/completions") {
            return endpoint
        }
        let trimmed = s.hasSuffix("/") ? String(s.dropLast()) : s
        return URL(string: trimmed + "/chat/completions") ?? endpoint
    }
}

enum PolishOutputCleaner {
    private static let leadingBoilerplatePatterns: [String] = [
        #"(?s)^根据[你您]?(?:给的|提供的)?内容[，,\s]*(?:我)?(?:已经|已)?(?:整理|优化)(?:好|完成)?(?:如下)?[：:\s]*"#,
        #"(?s)^以下(?:是|为)?(?:整理|优化|结构化整理)后?的?内容(?:如下)?[：:\s]*"#,
        #"(?s)^(?:整理|优化|结构化整理)(?:后?的?内容)?(?:如下)?[：:\s]*"#,
    ]

    static func clean(_ content: String) -> String {
        var output = content.trimmingCharacters(in: .whitespacesAndNewlines)
        output = stripMarkdownFence(from: output)

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

    private static func stripMarkdownFence(from text: String) -> String {
        guard text.hasPrefix("```"), text.hasSuffix("```") else { return text }
        var lines = text.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return text }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
