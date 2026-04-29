import XCTest
@testable import OpenLessASR
import OpenLessCore

/// AliyunParaformerASRProvider 的纯结构断言。
///
/// 注：实际 WebSocket 握手 + run-task 协议交互需要真实 DashScope 端点，单元测试里不做集成验证。
final class AliyunParaformerASRProviderTests: XCTestCase {

    // MARK: - info 元数据

    func test_info_reports_aliyun_paraformer_streaming_provider() {
        // Arrange
        let provider = AliyunParaformerASRProvider(apiKey: "sk-test")

        // Act
        let info = provider.info

        // Assert
        XCTAssertEqual(info.providerId, "aliyun-paraformer")
        XCTAssertEqual(info.mode, .streaming)
        XCTAssertFalse(info.supportsHotwords, "vocabulary_id 上传 v1 不做，supportsHotwords 应为 false")
        XCTAssertTrue(info.supportsLanguageHint)
        XCTAssertTrue(info.supportsPartialResults)
    }

    func test_info_displayName_is_localized_chinese() {
        // Arrange
        let provider = AliyunParaformerASRProvider(apiKey: "sk-test")

        // Act
        let displayName = provider.info.displayName

        // Assert
        XCTAssertEqual(displayName, "阿里通义 Paraformer")
    }

    // MARK: - 批量入口在流式 provider 上必须明确不支持

    func test_transcribeBatch_throws_unsupportedMode() async {
        // Arrange
        let provider = AliyunParaformerASRProvider(apiKey: "sk-test")
        let pcm = Data(repeating: 0, count: 32_000) // 1 秒静音

        // Act / Assert
        do {
            _ = try await provider.transcribeBatch(
                pcm: pcm,
                sampleRate: 16_000,
                channels: 1,
                language: "zh-CN",
                hotwords: []
            )
            XCTFail("transcribeBatch 应抛 ASRError.unsupportedMode")
        } catch let error as ASRError {
            XCTAssertEqual(error, .unsupportedMode)
        } catch {
            XCTFail("应抛 ASRError，实际抛: \(error)")
        }
    }
}
