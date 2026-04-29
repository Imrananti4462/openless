import XCTest
@testable import OpenLessASR
import OpenLessCore

/// CustomOpenAIWhisperASRProvider + WAVHeader 的纯结构断言。
///
/// 没有真实 OpenAI 端点的 multipart 上传集成验证；那部分留给手工冒烟。
final class CustomOpenAIWhisperASRProviderTests: XCTestCase {

    // MARK: - info 元数据

    func test_info_reports_whisper_batch_provider() {
        // Arrange
        let provider = CustomOpenAIWhisperASRProvider(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test"
        )

        // Act
        let info = provider.info

        // Assert
        XCTAssertEqual(info.providerId, "custom-openai-whisper")
        XCTAssertEqual(info.mode, .batch)
        XCTAssertFalse(info.supportsHotwords, "Whisper 仅支持 prompt 软提示，不算真热词")
        XCTAssertTrue(info.supportsLanguageHint)
        XCTAssertFalse(info.supportsPartialResults)
    }

    func test_info_displayName_is_localized_chinese() {
        // Arrange
        let provider = CustomOpenAIWhisperASRProvider(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test"
        )

        // Act
        let displayName = provider.info.displayName

        // Assert
        XCTAssertEqual(displayName, "自定义 OpenAI 兼容 (Whisper)")
    }

    // MARK: - 流式入口在批量 provider 上必须明确不支持

    func test_openStreamingSession_throws_unsupportedMode() async {
        // Arrange
        let provider = CustomOpenAIWhisperASRProvider(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: "sk-test"
        )

        // Act / Assert
        do {
            _ = try await provider.openStreamingSession(language: "zh-CN", hotwords: [])
            XCTFail("openStreamingSession 应抛 ASRError.unsupportedMode")
        } catch let error as ASRError {
            XCTAssertEqual(error, .unsupportedMode)
        } catch {
            XCTFail("应抛 ASRError，实际抛: \(error)")
        }
    }

    // MARK: - WAV header 构造

    func test_wavHeader_wraps_pcm_with_riff_format() {
        // Arrange：1 秒 16k mono Int16 PCM = 32000 字节静音。
        let pcm = Data(repeating: 0, count: 32_000)

        // Act
        let wav = WAVHeader.wrap(pcm: pcm, sampleRate: 16_000, channels: 1)

        // Assert
        // 总长 = 44 (header) + 32000 (data)
        XCTAssertEqual(wav.count, 44 + 32_000)

        // RIFF / WAVE / fmt / data 标识
        XCTAssertEqual(Array(wav[0..<4]), Array("RIFF".utf8))
        XCTAssertEqual(Array(wav[8..<12]), Array("WAVE".utf8))
        XCTAssertEqual(Array(wav[12..<16]), Array("fmt ".utf8))
        XCTAssertEqual(Array(wav[36..<40]), Array("data".utf8))

        // chunkSize（offset 4-7）= 36 + dataSize
        let chunkSize = readUInt32LE(wav, at: 4)
        XCTAssertEqual(chunkSize, UInt32(36 + 32_000))

        // fmt chunk size（offset 16-19）= 16
        XCTAssertEqual(readUInt32LE(wav, at: 16), 16)

        // audio format（offset 20-21）= 1 (PCM)
        XCTAssertEqual(readUInt16LE(wav, at: 20), 1)

        // num channels（offset 22-23）= 1
        XCTAssertEqual(readUInt16LE(wav, at: 22), 1)

        // sample rate（offset 24-27）= 16000
        XCTAssertEqual(readUInt32LE(wav, at: 24), 16_000)

        // byte rate（offset 28-31）= sampleRate * channels * bitsPerSample / 8 = 32000
        XCTAssertEqual(readUInt32LE(wav, at: 28), 32_000)

        // block align（offset 32-33）= channels * bitsPerSample / 8 = 2
        XCTAssertEqual(readUInt16LE(wav, at: 32), 2)

        // bits per sample（offset 34-35）= 16
        XCTAssertEqual(readUInt16LE(wav, at: 34), 16)

        // data size（offset 40-43）= pcm.count
        XCTAssertEqual(readUInt32LE(wav, at: 40), 32_000)
    }

    func test_wavHeader_records_stereo_44k_correctly() {
        // Arrange：44.1 kHz stereo 测一下非默认参数也写对了。
        let pcm = Data(repeating: 0, count: 4_000)

        // Act
        let wav = WAVHeader.wrap(pcm: pcm, sampleRate: 44_100, channels: 2)

        // Assert
        XCTAssertEqual(readUInt16LE(wav, at: 22), 2)              // channels
        XCTAssertEqual(readUInt32LE(wav, at: 24), 44_100)         // sample rate
        XCTAssertEqual(readUInt32LE(wav, at: 28), 44_100 * 2 * 2) // byte rate = sr * ch * bytesPerSample
        XCTAssertEqual(readUInt16LE(wav, at: 32), 4)              // block align = ch * bytesPerSample
    }

    // MARK: - 辅助

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return b0 | (b1 << 8)
    }
}
