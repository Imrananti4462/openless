import Foundation
import OpenLessCore

/// 开发期凭据存储：JSON 文件，路径 `~/.openless/credentials.json`，权限 0600。
///
/// 内部存储为 v1 schema（`CredentialsSchemaV1`）：版本化结构 + provider 分节。
/// 旧的 v0 扁平字典文件首次加载时会被自动迁移：
/// 1. 备份原文件到 `credentials.v0.bak.<timestamp>.json`
/// 2. 翻译 v0 字段 → v1 schema
/// 3. 原子写新 v1 文件（tmp + rename + 0600）
///
/// 公开 API（`get` / `set` / `remove` / `snapshot`）保留与 v0 一致的"扁平账号 key"语义，
/// 内部把 `volcengine.app_key` 这样的 key 路由到 `providers.asr.volcengine.appKey` 字段。
/// 这让 SettingsHubTab / Sidebar 等老调用点不用改字段访问就能继续工作。
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

    private let directoryURL: URL
    private let fileURL: URL
    private let lock = NSLock()
    private var schema: CredentialsSchemaV1 = .empty
    private var loaded = false
    /// 累积过的非致命加载错误（unparseable / futureVersion 等）。
    /// 调用方可读出来用于 UI 提示；这里**不抛出**，否则 vault 单例初始化路径会全线崩。
    private var lastLoadError: CredentialsError?

    public init(directoryURL: URL? = nil) {
        let dir = directoryURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openless", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.directoryURL = dir
        self.fileURL = dir.appendingPathComponent("credentials.json")
    }

    // MARK: - 公开 API（保持 v0 兼容签名）

    /// 按账号 key 写入凭据。空字符串等价于删除。
    /// 写入后立即落盘（atomic rename + 0600）。
    public func set(_ value: String, for account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()

        let normalized = value
        if normalized.isEmpty {
            removeAccountLocked(account)
        } else {
            setAccountLocked(account, value: normalized)
        }
        try writeLocked()
    }

    /// 按账号 key 读取凭据。返回 nil 表示未设置 / 空。
    public func get(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return readAccountLocked(account)
    }

    /// 按账号 key 删除凭据；写入失败被吞（这是历史 v0 行为）。
    public func remove(_ account: String) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        removeAccountLocked(account)
        try? writeLocked()
    }

    /// 一次性把所有账号读出来；调用方在内存里持有，避免每次会话都打 IO。
    /// snapshot 跟随当前 active provider；切换 active LLM 后再次调用会反映新的 provider 字段。
    public func snapshot() -> CredentialsSnapshot {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        let volc = schema.providers.asr[schema.active.asr]
        let llm = schema.providers.llm[schema.active.llm]
        return CredentialsSnapshot(
            volcengineAppKey: volc?.appKey,
            volcengineAccessKey: volc?.accessKey,
            volcengineResourceId: volc?.resourceId,
            arkApiKey: llm?.apiKey,
            arkModelId: llm?.model,
            arkEndpoint: llm?.baseURL
        )
    }

    /// 暴露当前内存中 v1 schema 的副本（值类型，安全）。
    public func currentSchema() -> CredentialsSchemaV1 {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        return schema
    }

    /// 最近一次 `loadIfNeeded` 期间累积的非致命错误（如果有）。
    public func loadError() -> CredentialsError? {
        lock.lock()
        defer { lock.unlock() }
        return lastLoadError
    }

    // MARK: - 加载 / 迁移

    private func loadIfNeededLocked() {
        guard !loaded else { return }
        loaded = true

        // 文件不存在 → 空 v1 schema，不创建文件（首次 set 时再写）。
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            schema = .empty
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // 读取失败：保留 empty schema，不删原文件。
            lastLoadError = .ioError("读取 credentials.json 失败: \(error.localizedDescription)")
            schema = .empty
            return
        }

        let result: CredentialsMigration.Result
        do {
            result = try CredentialsMigration.parseAndMigrate(rawData: data, fileURL: fileURL)
        } catch let credErr as CredentialsError {
            // 解析失败 / 未来版本：原文件不动；schema 保持 empty。
            lastLoadError = credErr
            schema = .empty
            return
        } catch {
            lastLoadError = .ioError(String(describing: error))
            schema = .empty
            return
        }

        schema = result.schema

        // v0 → v1：先备份原文件，再写出新 v1 文件（atomic）。
        if result.needsMigrationFromV0 {
            do {
                try backupV0FileLocked()
                try writeLocked()
            } catch let credErr as CredentialsError {
                lastLoadError = credErr
            } catch {
                lastLoadError = .ioError(String(describing: error))
            }
        }
    }

    /// 把当前 fileURL 处的 v0 文件 move 到 `credentials.v0.bak.<timestamp>[-N].json`。
    /// 时间戳用紧凑 ISO8601（`yyyyMMddTHHmmss`）。冲突时追加 `-1`、`-2` 后缀。
    private func backupV0FileLocked() throws {
        let timestamp = compactISO8601Timestamp(date: Date())
        var target = directoryURL.appendingPathComponent("credentials.v0.bak.\(timestamp).json")
        var suffix = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = directoryURL.appendingPathComponent("credentials.v0.bak.\(timestamp)-\(suffix).json")
            suffix += 1
        }

        do {
            try FileManager.default.moveItem(at: fileURL, to: target)
        } catch {
            throw CredentialsError.backupFailed(target)
        }
    }

    // MARK: - 写入

    /// 原子写：JSON → tmp → fsync → rename → 0600。
    private func writeLocked() throws {
        // 写之前过滤掉空 provider 节，保持 JSON 干净。
        let cleaned = cleanedSchema(schema)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(cleaned)
        } catch {
            throw CredentialsError.writeFailed(fileURL, "JSON 编码失败: \(error.localizedDescription)")
        }

        // 确保目录存在（直接调用 vault 而没经过 init 的边角情况）。
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let tmpURL = directoryURL.appendingPathComponent("credentials.json.tmp")
        // 防止上次写崩留下的残骸。
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }

        // 写 tmp + fsync。
        do {
            try data.write(to: tmpURL, options: [.atomic])
        } catch {
            throw CredentialsError.writeFailed(tmpURL, "写 tmp 文件失败: \(error.localizedDescription)")
        }
        // 显式 fsync 一下，防止 rename 后元数据丢失。
        if let fh = try? FileHandle(forWritingTo: tmpURL) {
            try? fh.synchronize()
            try? fh.close()
        }

        // 原子替换：rename(tmp, target)。如果 target 已存在，replaceItemAt 也能正确处理。
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: fileURL)
            }
        } catch {
            // 失败时清理 tmp，避免残骸误导下一次。
            try? FileManager.default.removeItem(at: tmpURL)
            throw CredentialsError.writeFailed(fileURL, "rename 失败: \(error.localizedDescription)")
        }

        // 设置权限 0600。
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            throw CredentialsError.writeFailed(fileURL, "设置权限失败: \(error.localizedDescription)")
        }

        // 兜底：万一 replaceItemAt 留下了 tmp（不同 macOS 行为不一致），统一清理。
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    /// 写盘前过滤：移除 isAllEmpty 的 provider 节。
    private func cleanedSchema(_ s: CredentialsSchemaV1) -> CredentialsSchemaV1 {
        var out = s
        out.providers.asr = out.providers.asr.filter { !$0.value.isAllEmpty }
        out.providers.llm = out.providers.llm.filter { !$0.value.isAllEmpty }
        return out
    }

    // MARK: - 账号 key → v1 字段路由

    private func readAccountLocked(_ account: String) -> String? {
        // ASR 路径锁定到 active ASR provider；LLM 路径锁定到 active LLM provider。
        // 一旦用户在 LLM 设置页切换 active（比如从 ark 切到 deepseek），老 UI 通过
        // `ark.*` 账号 key 看到的就是 deepseek 的字段——这是预期行为。
        let activeASR = schema.active.asr
        let activeLLM = schema.active.llm
        switch account {
        case CredentialAccount.volcengineAppKey:
            return schema.providers.asr[activeASR]?.appKey
        case CredentialAccount.volcengineAccessKey:
            return schema.providers.asr[activeASR]?.accessKey
        case CredentialAccount.volcengineResourceId:
            return schema.providers.asr[activeASR]?.resourceId
        case CredentialAccount.arkApiKey:
            return schema.providers.llm[activeLLM]?.apiKey
        case CredentialAccount.arkModelId:
            return schema.providers.llm[activeLLM]?.model
        case CredentialAccount.arkEndpoint:
            return schema.providers.llm[activeLLM]?.baseURL
        default:
            return nil
        }
    }

    private func setAccountLocked(_ account: String, value: String) {
        switch account {
        case CredentialAccount.volcengineAppKey:
            mutateVolc { $0.appKey = value }
        case CredentialAccount.volcengineAccessKey:
            mutateVolc { $0.accessKey = value }
        case CredentialAccount.volcengineResourceId:
            mutateVolc { $0.resourceId = value }
        case CredentialAccount.arkApiKey:
            mutateArk { $0.apiKey = value }
        case CredentialAccount.arkModelId:
            mutateArk { $0.model = value }
        case CredentialAccount.arkEndpoint:
            mutateArk { $0.baseURL = value }
        default:
            // 未知 account：保持向后兼容，静默忽略。
            break
        }
    }

    private func removeAccountLocked(_ account: String) {
        switch account {
        case CredentialAccount.volcengineAppKey:
            mutateVolc { $0.appKey = nil }
        case CredentialAccount.volcengineAccessKey:
            mutateVolc { $0.accessKey = nil }
        case CredentialAccount.volcengineResourceId:
            mutateVolc { $0.resourceId = nil }
        case CredentialAccount.arkApiKey:
            mutateArk { $0.apiKey = nil }
        case CredentialAccount.arkModelId:
            mutateArk { $0.model = nil }
        case CredentialAccount.arkEndpoint:
            mutateArk { $0.baseURL = nil }
        default:
            break
        }
    }

    private func mutateVolc(_ apply: (inout CredentialsProviderASRVolcengine) -> Void) {
        // 老路径：`volcengine.*` 账号 key 始终路由到 active ASR provider。
        // M1 active.asr 永远是 "volcengine"，未来加供应商时这里也无需再改。
        let key = schema.active.asr
        var existing = schema.providers.asr[key] ?? CredentialsProviderASRVolcengine()
        apply(&existing)
        if existing.isAllEmpty {
            schema.providers.asr.removeValue(forKey: key)
        } else {
            schema.providers.asr[key] = existing
        }
    }

    private func mutateArk(_ apply: (inout CredentialsProviderLLMEntry) -> Void) {
        // 老路径：`ark.*` 账号 key 始终路由到 active LLM provider。
        // 这让 SettingsHubTab 等老 UI 在新 schema 下保持原本的"豆包"语义。
        let key = schema.active.llm
        var existing = schema.providers.llm[key] ?? CredentialsProviderLLMEntry()
        apply(&existing)
        if existing.isAllEmpty {
            schema.providers.llm.removeValue(forKey: key)
        } else {
            schema.providers.llm[key] = existing
        }
    }
}

// MARK: - 多 LLM provider 支持（B-3）

extension CredentialsVault {
    /// 当前选中的 LLM provider id；getter 同时承担"loadIfNeeded"。
    public var activeLLMProviderId: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            loadIfNeededLocked()
            return schema.active.llm
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            loadIfNeededLocked()
            guard schema.active.llm != newValue else { return }
            schema.active.llm = newValue
            try? writeLocked()
        }
    }

    /// 列出所有已配置的 LLM provider id（包含还没填 apiKey 的占位条目）。
    /// 用于设置页的 picker；当前 active 即便条目不存在也会被列出，避免"切换-删除"流程把用户卡死。
    public var configuredLLMProviderIds: [String] {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        var ids = Set(schema.providers.llm.keys)
        ids.insert(schema.active.llm)
        return ids.sorted()
    }

    /// 读出某个 provider 的完整 OpenAICompatibleConfig；缺 apiKey 也仍然返回（让 UI 显示空表单）。
    /// baseURL / displayName 缺省时用 registry 兜底；都没兜底则返回 nil。
    public func llmProviderConfig(for providerId: String) -> OpenAICompatibleConfig? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        let entry = schema.providers.llm[providerId]
        let preset = LLMProviderRegistry.preset(for: providerId)

        let displayName: String
        if let stored = entry?.displayName, !stored.isEmpty {
            displayName = stored
        } else if let preset {
            displayName = preset.displayName
        } else {
            displayName = providerId
        }

        let baseURL: URL
        if let stored = entry?.baseURL,
           !stored.isEmpty,
           let parsed = URL(string: stored.trimmingCharacters(in: .whitespacesAndNewlines)) {
            baseURL = parsed
        } else if let preset {
            baseURL = preset.defaultBaseURL
        } else {
            // 自定义 provider 又没填 baseURL：无法构造 config。
            return nil
        }

        let model = entry?.model ?? preset?.defaultModel ?? ""
        let apiKey = entry?.apiKey ?? ""
        let temperature = entry?.temperature ?? 0.3
        let extraHeaders = entry?.extraHeaders ?? [:]

        return OpenAICompatibleConfig(
            providerId: providerId,
            displayName: displayName,
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            extraHeaders: extraHeaders,
            temperature: temperature
        )
    }

    /// 写一份完整的 OpenAICompatibleConfig 到对应 provider id 下。
    /// - 预设 provider：与 registry 默认值相同的 baseURL / displayName 不写盘（保持 JSON 简洁，
    ///   未来 registry 调整时不会被旧文件锁死）。
    /// - 自定义 provider：所有字段都写入（包括 displayName，因为没有 registry 可以兜底）。
    public func setLLMProviderConfig(_ config: OpenAICompatibleConfig) {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()

        let preset = LLMProviderRegistry.preset(for: config.providerId)
        var entry = schema.providers.llm[config.providerId] ?? CredentialsProviderLLMEntry()

        // displayName：与 preset 相同就不写，UI 始终从 registry 拿。
        if let preset, preset.displayName == config.displayName {
            entry.displayName = nil
        } else {
            let trimmed = config.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.displayName = trimmed.isEmpty ? nil : trimmed
        }

        // baseURL：与 preset.defaultBaseURL 相同就不写。
        if let preset, preset.defaultBaseURL == config.baseURL {
            entry.baseURL = nil
        } else {
            entry.baseURL = config.baseURL.absoluteString
        }

        // model：与 preset.defaultModel 相同 / 为空 → 视为"未覆盖"，不写盘。
        if let preset, !preset.defaultModel.isEmpty, preset.defaultModel == config.model {
            entry.model = nil
        } else {
            let trimmed = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.model = trimmed.isEmpty ? nil : trimmed
        }

        // apiKey：空字符串 → nil，避免落出 `"apiKey": ""`。
        let trimmedKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.apiKey = trimmedKey.isEmpty ? nil : trimmedKey

        // temperature：默认 0.3 视为未覆盖。
        entry.temperature = config.temperature == 0.3 ? nil : config.temperature

        // extraHeaders：空 dict 收敛成 nil。
        entry.extraHeaders = config.extraHeaders.isEmpty ? nil : config.extraHeaders

        if entry.isAllEmpty {
            schema.providers.llm.removeValue(forKey: config.providerId)
        } else {
            schema.providers.llm[config.providerId] = entry
        }
        try? writeLocked()
    }

    /// 删除某个 LLM provider；不允许删 active provider。
    /// 需要先把 `activeLLMProviderId` 切到别的 id，再删旧条目。
    public func removeLLMProvider(_ providerId: String) throws {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()

        if schema.active.llm == providerId {
            throw CredentialsError.cannotRemoveActiveProvider(providerId)
        }
        guard schema.providers.llm[providerId] != nil else { return }
        schema.providers.llm.removeValue(forKey: providerId)
        try writeLocked()
    }
}

// MARK: - 多 ASR provider 支持（C-2 切换器）

extension CredentialsVault {
    /// 当前选中的 ASR provider id；getter 同时承担"loadIfNeeded"。
    /// 切换 active ASR 后会通过写盘把新值持久化；调用方应 post `.openLessCredentialsChanged`
    /// 让 DictationCoordinator 等订阅方刷新缓存（这里不直接 post，避免循环依赖）。
    public var activeASRProviderId: String {
        get {
            lock.lock()
            defer { lock.unlock() }
            loadIfNeededLocked()
            return schema.active.asr
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            loadIfNeededLocked()
            guard schema.active.asr != newValue else { return }
            schema.active.asr = newValue
            try? writeLocked()
        }
    }

    /// 列出所有"可选"的 ASR provider id：
    /// - schema 里已有条目的 id（用户填过火山字段就会落到 providers.asr 里）
    /// - registry 预设的 id（保证 Apple Speech 这种"无字段"provider 也能出现在 picker 里）
    /// - 当前 active id（即便条目不存在也要列出，避免"切换-删除"流程把用户卡死）
    public var configuredASRProviderIds: [String] {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeededLocked()
        var ids = Set(schema.providers.asr.keys)
        ids.insert(schema.active.asr)
        for preset in ASRProviderRegistry.presets {
            ids.insert(preset.providerId)
        }
        return ids.sorted()
    }
}

// MARK: - 时间戳工具

/// 紧凑 ISO8601 时间戳，例如 `20260429T103045`。固定 UTC，避免 DST。
@inlinable
func compactISO8601Timestamp(date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyyyMMdd'T'HHmmss"
    return formatter.string(from: date)
}

// MARK: - Account constants

public enum CredentialAccount {
    public static let volcengineAppKey = "volcengine.app_key"
    public static let volcengineAccessKey = "volcengine.access_key"
    public static let volcengineResourceId = "volcengine.resource_id"
    public static let arkApiKey = "ark.api_key"
    public static let arkModelId = "ark.model_id"
    public static let arkEndpoint = "ark.endpoint"
}

// MARK: - Snapshot

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
