import XCTest
@testable import OpenLessCore

/// LLMProviderRegistry 的静态健康检查：5 家供应商各 1 条，id 不重复，URL 合法。
///
/// 这些断言看起来很无聊，但 registry 直接被设置 UI 和 vault 兜底逻辑用，
/// 漏一条都会变成"用户加不了 provider / baseURL 解不出来"的运行期 bug。
final class LLMProviderRegistryTests: XCTestCase {

    func test_presets_haveExpectedCount() {
        // Arrange
        let presets = LLMProviderRegistry.presets

        // Act / Assert
        XCTAssertEqual(presets.count, 5, "B-3 计划列出的预设是 ark / openai / aliyun-dashscope / deepseek / moonshot")
    }

    func test_presets_includeAllExpectedProviderIds() {
        // Arrange
        let expected: Set<String> = ["ark", "openai", "aliyun-dashscope", "deepseek", "moonshot"]

        // Act
        let actualIds = Set(LLMProviderRegistry.presets.map(\.providerId))

        // Assert
        XCTAssertEqual(actualIds, expected)
    }

    func test_presets_haveUniqueProviderIds() {
        // Arrange
        let ids = LLMProviderRegistry.presets.map(\.providerId)

        // Act / Assert
        XCTAssertEqual(Set(ids).count, ids.count, "providerId 必须唯一，否则 vault 会被互相覆盖")
    }

    func test_presets_haveValidBaseURLs() {
        for preset in LLMProviderRegistry.presets {
            // Arrange
            let url = preset.defaultBaseURL

            // Act / Assert：URL 必须是 https + 有 host
            XCTAssertEqual(url.scheme, "https", "preset \(preset.providerId) 的 baseURL 必须是 https，避免网络层降级")
            XCTAssertNotNil(url.host, "preset \(preset.providerId) 的 baseURL 必须有 host")
        }
    }

    func test_arkPreset_hasEmptyDefaultModel() {
        // Ark 的 defaultModel 故意留空——endpoint id 是用户在控制台拿到的 hash，
        // 不能预设。如果哪天默认填了一个看起来像 model 的字符串，UI 会误导用户。
        let ark = LLMProviderRegistry.preset(for: "ark")
        XCTAssertNotNil(ark)
        XCTAssertEqual(ark?.defaultModel, "")
    }

    func test_nonArkPresets_haveDefaultModel() {
        // OpenAI / DeepSeek / Moonshot / DashScope 都给了一个开箱即用的 model。
        for preset in LLMProviderRegistry.presets where preset.providerId != "ark" {
            XCTAssertFalse(preset.defaultModel.isEmpty, "preset \(preset.providerId) 应当有 defaultModel")
        }
    }

    func test_presets_haveNonEmptyHelpText() {
        for preset in LLMProviderRegistry.presets {
            XCTAssertFalse(preset.helpText.isEmpty, "preset \(preset.providerId) 的 helpText 不能为空")
        }
    }

    func test_preset_lookup_returnsRegistered() {
        for preset in LLMProviderRegistry.presets {
            let resolved = LLMProviderRegistry.preset(for: preset.providerId)
            XCTAssertEqual(resolved, preset)
        }
    }

    func test_preset_lookup_unknownReturnsNil() {
        XCTAssertNil(LLMProviderRegistry.preset(for: "no-such-provider-xyz"))
    }

    func test_customSentinels_areDistinctFromPresetIds() {
        // 添加 sheet 用 customProviderId 区分"预设 vs 自定义"——它必须不在预设列表里，
        // 否则会被点击事件混淆。
        let presetIds = Set(LLMProviderRegistry.presets.map(\.providerId))
        XCTAssertFalse(presetIds.contains(LLMProviderRegistry.customProviderId))
    }
}
