import Foundation

/// ASR provider 预设注册表。
///
/// 集中维护"用户能开箱即用的 ASR 供应商列表"——M1 仅有火山引擎（云端流式）和
/// macOS 本地 Apple Speech（离线 / 系统内置）。UI 层用它生成 ASR Tab 的切换列表
/// 与帮助文案；运行期由 DictationCoordinator.makeASRProvider() 据 providerId 路由。
///
/// 与 `LLMProviderRegistry` 的差异：
/// - LLM 全是 OpenAI 兼容协议，可以共用同一份 OpenAICompatibleConfig；ASR 各家协议
///   差异大（火山自有 WebSocket framing，Apple 是系统 SDK，Whisper 是 HTTP 批量），
///   所以 preset 只暴露最小元数据（id + displayName + mode + helpText）；具体配置
///   字段由 provider 各自的 UI 段提供。
/// - 这里**不**暴露 baseURL / apiKey 之类的字段——provider 的字段由 SettingsHubTab
///   或新的 ASR Tab 各自承载（火山 3 字段在 SettingsHubTab；Apple Speech 无字段）。
public enum ASRProviderRegistry {
    /// 单条预设记录。
    public struct Preset: Sendable, Hashable {
        public let providerId: String
        public let displayName: String
        public let mode: ASRMode
        /// "这家 provider 是什么 / 怎么用" 的提示文案；UI 在切换列表下面展示。
        public let helpText: String

        public init(
            providerId: String,
            displayName: String,
            mode: ASRMode,
            helpText: String
        ) {
            self.providerId = providerId
            self.displayName = displayName
            self.mode = mode
            self.helpText = helpText
        }
    }

    /// M1 内置的 ASR provider 预设。
    /// 顺序即为 UI 列表的展示顺序——火山在前（旧用户默认），Apple Speech 在后。
    public static let presets: [Preset] = [
        Preset(
            providerId: "volcengine",
            displayName: "火山引擎 (Volcengine)",
            mode: .streaming,
            helpText: "需要在火山引擎控制台获取 App ID / Access Token / Resource ID。"
        ),
        Preset(
            providerId: "apple-speech",
            displayName: "macOS 本地 (Apple Speech)",
            mode: .streaming,
            helpText: "使用 macOS 内置语音识别。免费、离线（zh-CN 在 Apple Silicon 上支持纯离线），不需要 API key。首次切换时系统会请求语音识别权限。"
        ),
    ]

    /// 根据 providerId 查预设；未知 id 返回 nil。
    public static func preset(for providerId: String) -> Preset? {
        presets.first { $0.providerId == providerId }
    }
}
