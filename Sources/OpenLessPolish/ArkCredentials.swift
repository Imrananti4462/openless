import Foundation

public struct ArkCredentials: Codable, Sendable, Equatable {
    public let apiKey: String
    public let modelId: String
    public let endpoint: URL

    public init(apiKey: String, modelId: String = ArkCredentials.defaultModelId, endpoint: URL = ArkCredentials.defaultEndpoint) {
        self.apiKey = apiKey
        self.modelId = modelId
        self.endpoint = endpoint
    }

    public static let defaultModelId = "deepseek-v3-2"
    public static let defaultEndpoint = URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")!
}
