import Foundation

/// 开发期凭据存储：明文 JSON，路径 `~/.openless/credentials.json`，权限 0600。
///
/// 为什么不用 Keychain：
/// 这个 .app 是 ad-hoc 签名（`codesign --sign -`），Keychain ACL 跟二进制 hash 强绑定。
/// 每次 `swift build` 重建后 hash 都变 → "始终允许"立刻作废 → 6 个账号 6 个弹窗。
/// 而且弹窗在主线程同步阻塞，会卡住录音/识别 hot path。
/// 上线前若需要更强机密性，再切回 Keychain（届时会有稳定的开发者签名）或叠层 AES。
///
/// 当前威胁模型：单用户开发机，0600 权限，只防同账户下的非特权进程。
public final class CredentialsVault: @unchecked Sendable {
    /// 仍保留这个常量，build-app.sh 等地方按 bundle id 引用它。
    public static let serviceName = "com.openless.app"
    public static let shared = CredentialsVault()

    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    private var loaded = false

    public init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openless", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.fileURL = dir.appendingPathComponent("credentials.json")
    }

    public func set(_ value: String, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        if value.isEmpty {
            cache.removeValue(forKey: account)
        } else {
            cache[account] = value
        }
        try writeLocked()
    }

    public func get(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return cache[account]
    }

    public func remove(_ account: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        cache.removeValue(forKey: account)
        try? writeLocked()
    }

    private func loadIfNeededLocked() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        cache = dict
    }

    private func writeLocked() throws {
        let data = try JSONEncoder().encode(cache)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}

public enum CredentialAccount {
    public static let volcengineAppKey = "volcengine.app_key"
    public static let volcengineAccessKey = "volcengine.access_key"
    public static let volcengineResourceId = "volcengine.resource_id"
    public static let arkApiKey = "ark.api_key"
    public static let arkModelId = "ark.model_id"
    public static let arkEndpoint = "ark.endpoint"
}

/// 一次性把所有账号读出来；调用方在内存里持有，避免每次会话都打 IO。
public struct CredentialsSnapshot: Sendable, Equatable {
    public let volcengineAppKey: String?
    public let volcengineAccessKey: String?
    public let volcengineResourceId: String?
    public let arkApiKey: String?
    public let arkModelId: String?
    public let arkEndpoint: String?

    public init(
        volcengineAppKey: String?,
        volcengineAccessKey: String?,
        volcengineResourceId: String?,
        arkApiKey: String?,
        arkModelId: String?,
        arkEndpoint: String?
    ) {
        self.volcengineAppKey = volcengineAppKey
        self.volcengineAccessKey = volcengineAccessKey
        self.volcengineResourceId = volcengineResourceId
        self.arkApiKey = arkApiKey
        self.arkModelId = arkModelId
        self.arkEndpoint = arkEndpoint
    }
}

extension CredentialsVault {
    public func snapshot() -> CredentialsSnapshot {
        CredentialsSnapshot(
            volcengineAppKey: get(CredentialAccount.volcengineAppKey),
            volcengineAccessKey: get(CredentialAccount.volcengineAccessKey),
            volcengineResourceId: get(CredentialAccount.volcengineResourceId),
            arkApiKey: get(CredentialAccount.arkApiKey),
            arkModelId: get(CredentialAccount.arkModelId),
            arkEndpoint: get(CredentialAccount.arkEndpoint)
        )
    }
}
