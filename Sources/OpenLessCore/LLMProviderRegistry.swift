import Foundation

/// LLM provider 预设注册表。
///
/// 集中维护"用户能开箱即用的供应商列表"——豆包(Ark)、OpenAI、阿里通义 DashScope、
/// DeepSeek、Moonshot——以及 baseURL / model / 帮助文案。UI 层用它生成添加 provider
/// 的下拉菜单与帮助提示，运行期则用它兜底未填写的 baseURL / displayName。
///
/// `customProviderId` 是占位常量，不是真正的"id"：用户在添加自定义 provider 时由 UI 收集
/// 一个 slug 写入 schema；这里仅用来在添加 sheet 中区分"预设 vs 自定义"。
public enum LLMProviderRegistry {
    /// 单条预设记录。
    public struct Preset: Sendable, Hashable {
        public let providerId: String
        public let displayName: String
        public let defaultBaseURL: URL
        /// 预设的默认 model。Ark 故意留空——endpoint id 必须由用户在控制台拿到再填。
        public let defaultModel: String
        /// "怎么拿到 API Key" 的提示文案，UI 在帮助 disclosure 里展示。
        public let helpText: String
        /// 供应商 API Key 页面（可选）。UI 给一个"打开"按钮。
        public let docsURL: URL?

        public init(
            providerId: String,
            displayName: String,
            defaultBaseURL: URL,
            defaultModel: String,
            helpText: String,
            docsURL: URL?
        ) {
            self.providerId = providerId
            self.displayName = displayName
            self.defaultBaseURL = defaultBaseURL
            self.defaultModel = defaultModel
            self.helpText = helpText
            self.docsURL = docsURL
        }
    }

    /// 5 家 OpenAI 兼容供应商的开箱即用预设。
    /// 顺序即为 UI 添加菜单里的展示顺序——第一个是 Ark（老用户迁移过来的默认）。
    public static let presets: [Preset] = [
        Preset(
            providerId: "ark",
            displayName: "豆包 (Ark)",
            defaultBaseURL: URL(string: "https://ark.cn-beijing.volces.com/api/v3")!,
            defaultModel: "",
            helpText: "在火山引擎方舟控制台创建 endpoint 并把 endpoint id 填到 Model；API Key 在「我的 API Key」页生成。",
            docsURL: URL(string: "https://www.volcengine.com/docs/82379/1099475")
        ),
        Preset(
            providerId: "openai",
            displayName: "OpenAI",
            defaultBaseURL: URL(string: "https://api.openai.com/v1")!,
            defaultModel: "gpt-4o-mini",
            helpText: "platform.openai.com 创建 API key；推荐 gpt-4o-mini（性价比）或 gpt-4o（高质量）。需国外网络。",
            docsURL: URL(string: "https://platform.openai.com/api-keys")
        ),
        Preset(
            providerId: "aliyun-dashscope",
            displayName: "阿里通义 (DashScope)",
            defaultBaseURL: URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!,
            defaultModel: "qwen-turbo",
            helpText: "百炼控制台「API-KEY 管理」生成 sk-...；推荐 qwen-turbo（快）或 qwen-plus（强）。",
            docsURL: URL(string: "https://help.aliyun.com/zh/model-studio/get-api-key")
        ),
        Preset(
            providerId: "deepseek",
            displayName: "DeepSeek",
            defaultBaseURL: URL(string: "https://api.deepseek.com/v1")!,
            defaultModel: "deepseek-chat",
            helpText: "platform.deepseek.com 创建 API key；推荐 deepseek-chat。",
            docsURL: URL(string: "https://platform.deepseek.com/api_keys")
        ),
        Preset(
            providerId: "moonshot",
            displayName: "Moonshot 月之暗面",
            defaultBaseURL: URL(string: "https://api.moonshot.cn/v1")!,
            defaultModel: "moonshot-v1-8k",
            helpText: "platform.moonshot.cn 创建 API key；推荐 moonshot-v1-8k（短）或 moonshot-v1-32k（长）。",
            docsURL: URL(string: "https://platform.moonshot.cn/console/api-keys")
        ),
    ]

    /// 自定义 provider 的占位 id（不是真实 providerId，仅用于 UI 添加菜单）。
    public static let customProviderId = "custom"
    public static let customDisplayName = "自定义 OpenAI 兼容"

    /// 根据 providerId 查预设；未知 id 返回 nil（自定义 provider 通常落到这里）。
    public static func preset(for providerId: String) -> Preset? {
        presets.first { $0.providerId == providerId }
    }
}
