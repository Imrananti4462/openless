import XCTest
import OpenLessCore
@testable import OpenLessPersistence

/// CredentialsVault 多 LLM provider 扩展（B-3）的集成测试。
///
/// 用例策略与 CredentialsMigrationTests 一致：每个 case 独立 temp 目录，
/// 通过 vault 的 public API 验证多 provider 行为。
final class CredentialsVaultMultiProviderTests: XCTestCase {

    // MARK: - 辅助

    private func makeTempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openless-multi-provider-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }
        return dir
    }

    /// 写一份 v0 字典文件（点号风格 key），让 vault 自动迁移。
    private func writeV0File(_ dict: [String: String], to dir: URL) throws {
        let url = dir.appendingPathComponent("credentials.json")
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        try data.write(to: url)
    }

    // MARK: - active provider id

    func test_freshInstall_activeLLMProviderId_defaultsToArk() {
        // Arrange
        let dir = makeTempDirectory()

        // Act
        let vault = CredentialsVault(directoryURL: dir)
        let active = vault.activeLLMProviderId

        // Assert：B-2 的默认 active.llm 是 "ark"，B-3 改成多 provider 后语义不变。
        XCTAssertEqual(active, "ark")
    }

    func test_v0Migrated_activeLLMProviderId_isArk() throws {
        // Arrange：典型迁移场景——从 v0 翻译过来 active.llm 应是 ark。
        let dir = makeTempDirectory()
        try writeV0File([
            "ark.api_key": "sk-ark",
            "ark.model_id": "deepseek-v3-2"
        ], to: dir)

        // Act
        let vault = CredentialsVault(directoryURL: dir)

        // Assert
        XCTAssertEqual(vault.activeLLMProviderId, "ark")
    }

    func test_setActive_persists() throws {
        // Arrange
        let dir = makeTempDirectory()

        // 先写一个 deepseek provider 进去（可以是空字段）。
        let vault = CredentialsVault(directoryURL: dir)
        vault.setLLMProviderConfig(OpenAICompatibleConfig(
            providerId: "deepseek",
            displayName: "DeepSeek",
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            apiKey: "sk-deepseek",
            model: "deepseek-chat"
        ))

        // Act
        vault.activeLLMProviderId = "deepseek"

        // Assert：内存视图
        XCTAssertEqual(vault.activeLLMProviderId, "deepseek")

        // 再开一个新 vault 实例确认落盘。
        let vault2 = CredentialsVault(directoryURL: dir)
        XCTAssertEqual(vault2.activeLLMProviderId, "deepseek")
    }

    // MARK: - configuredLLMProviderIds

    func test_configuredIds_emptyVault_returnsActive() {
        // Arrange
        let dir = makeTempDirectory()

        // Act
        let vault = CredentialsVault(directoryURL: dir)
        let ids = vault.configuredLLMProviderIds

        // Assert：vault 没有任何条目时，至少要返回 active id（picker 不能空）。
        XCTAssertEqual(ids, ["ark"])
    }

    func test_configuredIds_returnsAllConfigured() throws {
        // Arrange
        let dir = makeTempDirectory()
        let vault = CredentialsVault(directoryURL: dir)
        vault.setLLMProviderConfig(OpenAICompatibleConfig(
            providerId: "ark",
            displayName: "豆包 (Ark)",
            baseURL: URL(string: "https://ark.cn-beijing.volces.com/api/v3")!,
            apiKey: "ark-key",
            model: "ep-1"
        ))
        vault.setLLMProviderConfig(OpenAICompatibleConfig(
            providerId: "openai",
            displayName: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-openai",
            model: "gpt-4o-mini"
        ))
        vault.setLLMProviderConfig(OpenAICompatibleConfig(
            providerId: "deepseek",
            displayName: "DeepSeek",
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            apiKey: "sk-deepseek",
            model: "deepseek-chat"
        ))

        // Act
        let ids = vault.configuredLLMProviderIds

        // Assert：3 家全在；顺序 sorted。
        XCTAssertEqual(ids, ["ark", "deepseek", "openai"])
    }

    // MARK: - setLLMProviderConfig / llmProviderConfig 往返

    func test_setAndGetConfig_roundTrips() {
        // Arrange
        let dir = makeTempDirectory()
        let vault = CredentialsVault(directoryURL: dir)
        let cfg = OpenAICompatibleConfig(
            providerId: "deepseek",
            displayName: "DeepSeek",
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            apiKey: "sk-deep-12345",
            model: "deepseek-chat",
            extraHeaders: ["X-Custom": "value"],
            temperature: 0.5
        )

        // Act
        vault.setLLMProviderConfig(cfg)
        let back = vault.llmProviderConfig(for: "deepseek")

        // Assert：所有字段都应一一回读。
        XCTAssertEqual(back?.providerId, cfg.providerId)
        XCTAssertEqual(back?.displayName, cfg.displayName)
        XCTAssertEqual(back?.baseURL, cfg.baseURL)
        XCTAssertEqual(back?.apiKey, cfg.apiKey)
        XCTAssertEqual(back?.model, cfg.model)
        XCTAssertEqual(back?.temperature, cfg.temperature)
        XCTAssertEqual(back?.extraHeaders, cfg.extraHeaders)
    }

    func test_getConfig_unknownProvider_returnsNilWithoutPreset() {
        // Arrange
        let dir = makeTempDirectory()

        // Act
        let vault = CredentialsVault(directoryURL: dir)
        let cfg = vault.llmProviderConfig(for: "unknown-no-preset-xyz")

        // Assert：自定义 + 没有任何条目 + 没有预设 → 兜不出 baseURL，应返回 nil。
        XCTAssertNil(cfg)
    }

    func test_getConfig_presetWithoutEntry_usesPresetDefaults() {
        // Arrange
        let dir = makeTempDirectory()

        // Act
        let vault = CredentialsVault(directoryURL: dir)
        // openai 没有 entry，但有 preset；llmProviderConfig 应 fall back 到 preset 的 baseURL。
        let cfg = vault.llmProviderConfig(for: "openai")

        // Assert
        XCTAssertNotNil(cfg)
        XCTAssertEqual(cfg?.baseURL.absoluteString, "https://api.openai.com/v1")
        XCTAssertEqual(cfg?.displayName, "OpenAI")
        XCTAssertEqual(cfg?.model, "gpt-4o-mini")
        XCTAssertEqual(cfg?.apiKey, "")
    }

    // MARK: - removeLLMProvider

    func test_removeLLMProvider_blocksDeletingActive() throws {
        // Arrange
        let dir = makeTempDirectory()
        let vault = CredentialsVault(directoryURL: dir)

        // Act / Assert：默认 active 是 ark，不能删。
        XCTAssertThrowsError(try vault.removeLLMProvider("ark")) { err in
            guard case CredentialsError.cannotRemoveActiveProvider(let id) = err else {
                XCTFail("应该抛 cannotRemoveActiveProvider，实际：\(err)")
                return
            }
            XCTAssertEqual(id, "ark")
        }
    }

    func test_removeLLMProvider_removesNonActive() throws {
        // Arrange
        let dir = makeTempDirectory()
        let vault = CredentialsVault(directoryURL: dir)
        vault.setLLMProviderConfig(OpenAICompatibleConfig(
            providerId: "deepseek",
            displayName: "DeepSeek",
            baseURL: URL(string: "https://api.deepseek.com/v1")!,
            apiKey: "sk",
            model: "deepseek-chat"
        ))

        // Act
        try vault.removeLLMProvider("deepseek")

        // Assert
        XCTAssertNil(vault.llmProviderConfig(for: "deepseek")?.apiKey == "sk" ? () : ()) // sanity
        let ids = vault.configuredLLMProviderIds
        XCTAssertFalse(ids.contains("deepseek"))
    }

    func test_removeLLMProvider_unknownIdIsNoop() {
        // Arrange
        let dir = makeTempDirectory()
        let vault = CredentialsVault(directoryURL: dir)

        // Act / Assert：删一个根本不在的 id 不应抛错。
        XCTAssertNoThrow(try vault.removeLLMProvider("never-existed"))
    }

    // MARK: - 兼容老 API

    func test_legacyArkAccount_routesToActive() throws {
        // Arrange
        let dir = makeTempDirectory()
        let vault = CredentialsVault(directoryURL: dir)

        // 通过老 API 写入。
        try vault.set("legacy-key", for: CredentialAccount.arkApiKey)

        // Act：新的 multi-provider API 应能读出来。
        let cfg = vault.llmProviderConfig(for: "ark")

        // Assert
        XCTAssertEqual(cfg?.apiKey, "legacy-key")
    }
}
