import Foundation
import OpenLessCore

/// 通用的 OpenAI Chat Completions 协议 Provider 实现。
///
/// 适用所有遵循 OpenAI 协议的供应商：Volcengine Ark、OpenAI、阿里云 DashScope、
/// DeepSeek、Moonshot 等。差异完全由 `OpenAICompatibleConfig` 提供（baseURL / model /
/// apiKey / extraHeaders 等），不再为每个供应商维护一份 client。
///
/// 关键约束：
/// - 永远不会在日志里打印 `apiKey`（仅打印 URL / 状态码 / body 前 200 字符）。
/// - 对外抛出的错误统一为 `LLMError`，便于上层做无声降级（粘贴原文）。
/// - `URLSession` 可注入，方便测试用 URLProtocol 桩。
public final class OpenAICompatibleLLMProvider: LLMProvider, @unchecked Sendable {
    public let config: OpenAICompatibleConfig
    private let session: URLSession
    private let logger: (@Sendable (String) -> Void)?

    public init(
        config: OpenAICompatibleConfig,
        session: URLSession = .shared,
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.config = config
        self.session = session
        self.logger = logger
    }

    public func polish(
        rawText: String,
        mode: PolishMode,
        hotwords: [String]
    ) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw LLMError.missingCredentials
        }

        let url = Self.chatCompletionsURL(from: config.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.requestTimeout

        // 标准 header 先写：apiKey 永远走 Bearer，不走查询参数也不写进 body。
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        // extraHeaders 在最后写入，允许用户在确实需要时覆盖默认 header
        // （比如某些云服务要求自定义 Content-Type 或加上 X-Region）。
        for (key, value) in config.extraHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let systemPrompt = Self.composeSystemPrompt(for: mode, hotwords: hotwords)
        let userPrompt = PolishPrompts.userPrompt(for: rawText)

        // 不引入 thinking / reasoning 等供应商私有字段——这些应由 extraHeaders 或
        // 未来的扩展点处理。OpenAI 协议本身只保证以下字段被普遍兼容。
        let body: [String: Any] = [
            "model": config.model,
            "stream": false,
            "temperature": config.temperature,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 日志只打印 URL，不打印 body（body 里没有 apiKey，但仍可能含用户原话，
        // 隐私上能少打就少打）；apiKey 只在 Authorization header 里，不会被打印。
        logger?("[llm] POST \(url.absoluteString) provider=\(config.providerId) model=\(config.model)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw LLMError.timeout
            }
            throw LLMError.network(urlError as NSError)
        } catch {
            throw LLMError.network(error as NSError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.parseError("response is not HTTPURLResponse")
        }

        let bodyPreview = String(data: data, encoding: .utf8).map { String($0.prefix(Self.bodyPreviewLimit)) }
        logger?("[llm] HTTP \(http.statusCode) body=\(bodyPreview ?? "<binary>")")

        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.invalidResponse(statusCode: http.statusCode, body: bodyPreview)
        }

        return try Self.extractAssistantContent(from: data)
    }

    // MARK: - Helpers

    private static let bodyPreviewLimit = 200

    /// system prompt = mode 对应的基础规则 + （可选）hotwords 块。
    /// hotwords 为空时绝对不附加任何"词典"标题，避免给模型暗示。
    static func composeSystemPrompt(for mode: PolishMode, hotwords: [String]) -> String {
        let base = PolishPrompts.systemPrompt(for: mode)
        let cleaned = hotwords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return base }

        let list = cleaned.map { "- \($0)" }.joined(separator: "\n")
        return base + "\n\n热词（用户提供的正确写法，仅当原始转写明显是其误识别时才纠正，不做机械替换）：\n\(list)"
    }

    /// 既支持完整 URL（已带 /chat/completions），也支持 baseURL（自动追加）。
    static func chatCompletionsURL(from baseURL: URL) -> URL {
        let s = baseURL.absoluteString
        if s.hasSuffix("/chat/completions") {
            return baseURL
        }
        let trimmed = s.hasSuffix("/") ? String(s.dropLast()) : s
        return URL(string: trimmed + "/chat/completions") ?? baseURL
    }

    static func extractAssistantContent(from data: Data) throws -> String {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LLMError.parseError("not valid JSON: \(error.localizedDescription)")
        }

        guard let dict = json as? [String: Any] else {
            throw LLMError.parseError("response is not a JSON object")
        }
        guard let choices = dict["choices"] as? [[String: Any]], let first = choices.first else {
            throw LLMError.parseError("missing choices array")
        }
        guard let message = first["message"] as? [String: Any] else {
            throw LLMError.parseError("missing message in first choice")
        }
        guard let content = message["content"] as? String else {
            throw LLMError.parseError("message.content is not a string")
        }
        return content
    }
}
