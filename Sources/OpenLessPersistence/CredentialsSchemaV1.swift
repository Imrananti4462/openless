import Foundation

/// 凭据 v1 schema：版本化结构，按 provider 类别（asr / llm）→ providerId → 字段。
///
/// 设计要点：
/// - `providers.asr` / `providers.llm` 用字典（键为 providerId），未来加 provider 不需要再涨版本号。
/// - 每个 provider 子对象内部用 camelCase；所有字段都是 `String?`，缺省即"未设置"。
/// - provider 子对象在没有任何字段时**省略不写**（不输出空对象），保持 JSON 干净。
/// - `active` 必须存在并指向当前选中的 provider。M1 默认 `volcengine` / `ark`。
public struct CredentialsSchemaV1: Codable, Sendable, Equatable {
    public var version: Int
    public var providers: CredentialsProviders
    public var active: CredentialsActiveSelection

    public init(
        version: Int = 1,
        providers: CredentialsProviders = CredentialsProviders(),
        active: CredentialsActiveSelection = .defaults
    ) {
        self.version = version
        self.providers = providers
        self.active = active
    }

    /// 空 schema：无任何 provider 数据，active 用默认值。
    public static var empty: CredentialsSchemaV1 {
        CredentialsSchemaV1()
    }
}

// MARK: - Providers

/// `providers` 节点。M1 类型化为已知的两类（asr / llm），未来扩展时把字典加到这里。
public struct CredentialsProviders: Codable, Sendable, Equatable {
    /// ASR 类别：providerId → provider 配置。
    /// 通用 entry：火山（appKey/accessKey/resourceId）/ 阿里 paraformer（apiKey）/
    /// 自定义 OpenAI Whisper（apiKey/baseURL/model）共用同一份 entry。
    public var asr: [String: CredentialsProviderASREntry]
    /// LLM 类别：providerId → provider 配置。
    /// 任意 OpenAI 兼容供应商（ark / openai / aliyun-dashscope / deepseek / moonshot / 自定义）共用一份 entry。
    public var llm: [String: CredentialsProviderLLMEntry]

    public init(
        asr: [String: CredentialsProviderASREntry] = [:],
        llm: [String: CredentialsProviderLLMEntry] = [:]
    ) {
        self.asr = asr
        self.llm = llm
    }
}

/// 通用 ASR provider 凭据条目。
///
/// 各家 ASR provider 的字段需求差异较大（火山要 appKey/accessKey/resourceId；阿里 paraformer
/// 只要 apiKey；自定义 OpenAI 兼容 Whisper 需要 apiKey/baseURL/model），所以这里把所有可能用到的
/// 字段都设成可选——具体 provider 只填它需要的子集，其余字段保持 nil。
///
/// 自定义编码：nil 字段直接省略（不写 `"appKey": null`），保持 JSON 干净。
/// 这是**向后兼容**的——已经迁移到 v1 的 `providers.asr.volcengine` 仍然只包含
/// appKey/accessKey/resourceId 三个字段，新解码不会失败。
public struct CredentialsProviderASREntry: Codable, Sendable, Equatable, Hashable {
    /// 通用 API key（用于阿里 paraformer / 自定义 Whisper 等单 token 鉴权 provider）。
    public var apiKey: String?
    /// 自定义 OpenAI Whisper / 私有部署的 base URL。
    /// 字符串而不是 URL：编辑过程中用户输入可能是非法 URL，schema 不在这里早 fail。
    public var baseURL: String?
    /// 模型 id（自定义 Whisper 默认 `whisper-1`；预设 provider 一般固定 model 名，可省）。
    public var model: String?
    /// 火山 App Key（旧字段；保持向后兼容）。
    public var appKey: String?
    /// 火山 Access Key（旧字段；保持向后兼容）。
    public var accessKey: String?
    /// 火山 Resource ID（旧字段；保持向后兼容）。
    public var resourceId: String?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        model: String? = nil,
        appKey: String? = nil,
        accessKey: String? = nil,
        resourceId: String? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.appKey = appKey
        self.accessKey = accessKey
        self.resourceId = resourceId
    }

    /// 是否所有字段都是空 / nil。空 provider 在写盘时不应出现。
    public var isAllEmpty: Bool {
        isNilOrEmpty(apiKey)
            && isNilOrEmpty(baseURL)
            && isNilOrEmpty(model)
            && isNilOrEmpty(appKey)
            && isNilOrEmpty(accessKey)
            && isNilOrEmpty(resourceId)
    }

    private enum CodingKeys: String, CodingKey {
        case apiKey, baseURL, model, appKey, accessKey, resourceId
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(apiKey, forKey: .apiKey)
        try c.encodeIfPresent(baseURL, forKey: .baseURL)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(appKey, forKey: .appKey)
        try c.encodeIfPresent(accessKey, forKey: .accessKey)
        try c.encodeIfPresent(resourceId, forKey: .resourceId)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        appKey = try c.decodeIfPresent(String.self, forKey: .appKey)
        accessKey = try c.decodeIfPresent(String.self, forKey: .accessKey)
        resourceId = try c.decodeIfPresent(String.self, forKey: .resourceId)
    }
}

/// 兼容别名：B-2 / C-1 时期叫 `CredentialsProviderASRVolcengine`。
/// 通用化（C-3）后所有 ASR provider 共用同一类型。保留 typealias 让外部代码继续编译。
public typealias CredentialsProviderASRVolcengine = CredentialsProviderASREntry

/// 通用 OpenAI 兼容 LLM provider 凭据条目。
///
/// 同一份结构覆盖 Ark / OpenAI / DashScope / DeepSeek / Moonshot 以及用户自定义条目；
/// 需要呈现给 UI 的"友好名"放在 `displayName`（自定义时由用户指定，预设条目可缺省让 UI 兜底）。
///
/// 自定义编码：nil 字段直接省略；空 dict 的 `extraHeaders` 同样省略，保持 JSON 干净。
public struct CredentialsProviderLLMEntry: Codable, Sendable, Equatable, Hashable {
    /// 用户给该条目设置的展示名（自定义条目必填；预设条目允许 nil 由 UI 用 registry 兜底）。
    public var displayName: String?
    public var apiKey: String?
    /// 字符串而不是 URL：编辑过程中用户输入可能是非法 URL，schema 不在这里早 fail。
    public var baseURL: String?
    public var model: String?
    /// 该 provider 的 temperature 覆盖；为空时使用 `OpenAICompatibleConfig` 的默认值。
    public var temperature: Double?
    public var extraHeaders: [String: String]?

    public init(
        displayName: String? = nil,
        apiKey: String? = nil,
        baseURL: String? = nil,
        model: String? = nil,
        temperature: Double? = nil,
        extraHeaders: [String: String]? = nil
    ) {
        self.displayName = displayName
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.extraHeaders = extraHeaders
    }

    /// 是否所有字段都是空 / nil。
    public var isAllEmpty: Bool {
        isNilOrEmpty(displayName)
            && isNilOrEmpty(apiKey)
            && isNilOrEmpty(baseURL)
            && isNilOrEmpty(model)
            && temperature == nil
            && (extraHeaders?.isEmpty ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, apiKey, baseURL, model, temperature, extraHeaders
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(apiKey, forKey: .apiKey)
        try c.encodeIfPresent(baseURL, forKey: .baseURL)
        try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(temperature, forKey: .temperature)
        if let headers = extraHeaders, !headers.isEmpty {
            try c.encode(headers, forKey: .extraHeaders)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey)
        baseURL = try c.decodeIfPresent(String.self, forKey: .baseURL)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        extraHeaders = try c.decodeIfPresent([String: String].self, forKey: .extraHeaders)
    }
}

/// 兼容别名：B-2 时期叫 `CredentialsProviderLLMArk`。
/// 通用化后所有 LLM provider 共用同一类型。保留 typealias 让外部代码继续编译。
public typealias CredentialsProviderLLMArk = CredentialsProviderLLMEntry

// MARK: - Active selection

/// 当前激活的 provider。M1 默认 `volcengine` / `ark`。
public struct CredentialsActiveSelection: Codable, Sendable, Equatable {
    public var asr: String
    public var llm: String

    public init(asr: String, llm: String) {
        self.asr = asr
        self.llm = llm
    }

    public static var defaults: CredentialsActiveSelection {
        CredentialsActiveSelection(asr: defaultActiveASRProviderId, llm: defaultActiveLLMProviderId)
    }
}

// MARK: - 常量

public let defaultActiveASRProviderId = "volcengine"
public let defaultActiveLLMProviderId = "ark"
public let defaultArkBaseURL = "https://ark.cn-beijing.volces.com/api/v3"

// MARK: - 工具

@inlinable
func isNilOrEmpty(_ s: String?) -> Bool {
    guard let s else { return true }
    return s.isEmpty
}
