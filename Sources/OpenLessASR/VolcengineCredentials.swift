import Foundation

public struct VolcengineCredentials: Codable, Sendable, Equatable {
    public let appID: String        // X-Api-App-Key
    public let accessToken: String  // X-Api-Access-Key
    public let resourceID: String   // X-Api-Resource-Id, e.g. "volc.bigasr.sauc.duration"

    public init(appID: String, accessToken: String, resourceID: String) {
        self.appID = appID
        self.accessToken = accessToken
        self.resourceID = resourceID
    }

    public init(appKey: String, accessKey: String, resourceId: String) {
        self.init(appID: appKey, accessToken: accessKey, resourceID: resourceId)
    }

    public static let defaultResourceId = "volc.bigasr.sauc.duration"
}
