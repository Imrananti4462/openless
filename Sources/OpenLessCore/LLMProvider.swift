import Foundation

// LLMProvider 是文本润色层与具体大模型供应商之间的抽象。
// Ark / OpenAI / 阿里云 DashScope / DeepSeek / Moonshot 等都共用 OpenAI Chat
// Completions 协议，所以我们只需要一份 Provider 实现 + 不同的 OpenAICompatibleConfig。
//
// 该协议放在 OpenLessCore 是为了避免 Core 之外的层之间互相依赖：UI/设置层通过 Core
// 拿到 Provider 抽象，OpenLessPolish 提供具体实现。

public protocol LLMProvider: Sendable {
    /// 当前 Provider 使用的配置（baseURL / model / apiKey 等）。
    var config: OpenAICompatibleConfig { get }

    /// 把口语原始转写整理成最终输出文本。
    /// - Parameters:
    ///   - rawText: ASR 给出的原始文本，可能包含口癖、乱断句。
    ///   - mode: 润色模式（原文 / 轻度 / 结构化 / 正式）。
    ///   - hotwords: 用户词典里的热词，仅在非空时附加到 system prompt。
    /// - Returns: 经过模型整理后的纯文本，调用方仍需自己按业务做后处理（比如去前缀套话）。
    func polish(rawText: String, mode: PolishMode, hotwords: [String]) async throws -> String
}

/// OpenAI Chat Completions 协议下的通用 Provider 配置。
///
/// 同一份结构能描述 Ark / OpenAI / DashScope / DeepSeek / Moonshot 等所有 OpenAI 兼容端点。
/// `providerId` 是一个稳定字符串，用于在持久化里区分不同 provider；`displayName` 给 UI 用。
public struct OpenAICompatibleConfig: Codable, Sendable, Hashable {
    public let providerId: String
    public let displayName: String
    public let baseURL: URL
    public let apiKey: String
    public let model: String
    public let extraHeaders: [String: String]
    public let temperature: Double
    public let requestTimeout: TimeInterval

    public init(
        providerId: String,
        displayName: String,
        baseURL: URL,
        apiKey: String,
        model: String,
        extraHeaders: [String: String] = [:],
        temperature: Double = 0.3,
        requestTimeout: TimeInterval = 20
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.extraHeaders = extraHeaders
        self.temperature = temperature
        self.requestTimeout = requestTimeout
    }
}

/// LLMProvider 抛出的错误。
///
/// 这里没有把 URLError 直接暴露出去：URLError 不是 Sendable-friendly 的稳定值类型，
/// 而且我们要求 LLMError 是 Equatable（方便测试断言）。所以网络错误统一用 NSError 包装。
public enum LLMError: Error, Sendable, Equatable {
    /// 缺少调用所需的凭证（apiKey 为空等）。
    case missingCredentials
    /// HTTP 状态码非 2xx。`body` 是响应体的前若干字符（不是完整 body，避免日志过大）。
    case invalidResponse(statusCode: Int, body: String?)
    /// 解析响应 JSON 失败，附带定位信息。
    case parseError(String)
    /// 请求超时（URLError.timedOut 等）。
    case timeout
    /// 其他网络错误，原始错误用 NSError 携带 domain/code/userInfo，保持 Equatable。
    case network(NSError)
}
