import XCTest
@testable import OpenLessCore

/// ASRProviderRegistry 的静态健康检查：M1 应包含火山引擎 + Apple Speech 两条预设，
/// id 不重复、displayName 非空、mode 合法。
///
/// 这些断言看起来很无聊，但 registry 直接被 ASR Tab 的 chip 列表与 vault 兜底逻辑用，
/// 漏一条都会变成"用户切不了 ASR / picker 空白"的运行期 bug。
final class ASRProviderRegistryTests: XCTestCase {

    func test_presets_haveExpectedCount() {
        // Arrange
        let presets = ASRProviderRegistry.presets

        // Act / Assert
        XCTAssertEqual(presets.count, 2, "M1 计划列出的 ASR 预设是 volcengine / apple-speech")
    }

    func test_presets_includeAllExpectedProviderIds() {
        // Arrange
        let expected: Set<String> = ["volcengine", "apple-speech"]

        // Act
        let actualIds = Set(ASRProviderRegistry.presets.map(\.providerId))

        // Assert
        XCTAssertEqual(actualIds, expected)
    }

    func test_presets_haveUniqueProviderIds() {
        // Arrange
        let ids = ASRProviderRegistry.presets.map(\.providerId)

        // Act / Assert
        XCTAssertEqual(Set(ids).count, ids.count, "providerId 必须唯一，否则 vault 会被互相覆盖")
    }

    func test_presets_haveNonEmptyDisplayName() {
        for preset in ASRProviderRegistry.presets {
            XCTAssertFalse(preset.displayName.isEmpty, "preset \(preset.providerId) 的 displayName 不能为空")
        }
    }

    func test_presets_haveNonEmptyHelpText() {
        for preset in ASRProviderRegistry.presets {
            XCTAssertFalse(preset.helpText.isEmpty, "preset \(preset.providerId) 的 helpText 不能为空")
        }
    }

    func test_volcenginePreset_isStreaming() {
        // Arrange
        let preset = ASRProviderRegistry.preset(for: "volcengine")

        // Act / Assert
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.mode, .streaming)
    }

    func test_appleSpeechPreset_isStreaming() {
        // Arrange
        let preset = ASRProviderRegistry.preset(for: "apple-speech")

        // Act / Assert
        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.mode, .streaming)
    }

    func test_preset_lookup_returnsRegistered() {
        for preset in ASRProviderRegistry.presets {
            let resolved = ASRProviderRegistry.preset(for: preset.providerId)
            XCTAssertEqual(resolved, preset)
        }
    }

    func test_preset_lookup_unknownReturnsNil() {
        XCTAssertNil(ASRProviderRegistry.preset(for: "no-such-provider-xyz"))
    }
}
