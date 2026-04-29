import Foundation
import OpenLessCore

// CustomOpenAIWhisperASRProvider —— OpenAI 兼容批量 ASR provider。
//
// 协议要点（详见 docs/plans/provider-abstraction.md §4.5）：
//   1. 端点：`POST <baseURL>/audio/transcriptions`，multipart/form-data。
//   2. 鉴权：`Authorization: Bearer <apiKey>`。
//   3. 入参：file（音频字节，本实现包成 16 kHz / 16-bit / mono WAV）+ model（默认 whisper-1）+
//      language（如 "zh"）+ 可选 prompt（hotwords 拼接，软提示，不保证生效）。
//   4. 响应：`{"text": "..."}`。错误标准 OpenAI 形态。
//
// V1 限制（与 §4.5 对齐）：
//   - 单次硬上限 25 MB（multipart body 超过 → 413）。包成 WAV 后 PCM ~ 32 KB/s @ 16k mono，
//     约 13 分钟到顶。这里在 transcribeBatch 入口就先按 25 MB 截断 / fail，避免上传后才被服务端拒。
//   - hotwords 仅作 prompt 注入，软提示——`supportsHotwords=false`。Whisper-1 的 prompt 看后 224
//     tokens；gpt-4o 系列更宽容，但 OpenAI 官方明确"不保证精确替换"。
//   - 流式入口 (`openStreamingSession`) 直接抛 `.unsupportedMode`。
//
// V1 集成范围：
//   - DictationCoordinator 暂未实现"录完整体上传"分支（streaming dispatch only）。本 provider
//     已经独立可用——可以在单元测试里直接传 PCM 调；coordinator 的 batch 路径 TODO 后续补。

public final class CustomOpenAIWhisperASRProvider: ASRProvider {
    public let info: ASRProviderInfo
    private let baseURL: URL
    private let apiKey: String
    private let model: String
    private let session: URLSession
    private let logger: (@Sendable (String) -> Void)?

    /// OpenAI Whisper 单次上传的硬上限（25 MB）。包好 WAV 后超过此阈值直接 fail。
    public static let maxUploadBytes: Int = 25 * 1024 * 1024
    /// 网络超时（覆盖上传 + 服务端转录 + 抖动）。
    public static let requestTimeoutSeconds: TimeInterval = 60

    public init(
        baseURL: URL,
        apiKey: String,
        model: String = "whisper-1",
        session: URLSession = .shared,
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.session = session
        self.logger = logger
        self.info = ASRProviderInfo(
            providerId: "custom-openai-whisper",
            displayName: "自定义 OpenAI 兼容 (Whisper)",
            mode: .batch,
            // prompt 注入只是软提示，不算真热词。
            supportsHotwords: false,
            supportsLanguageHint: true,
            supportsPartialResults: false
        )
    }

    public func openStreamingSession(
        language: String,
        hotwords: [String]
    ) async throws -> ASRStreamingSession {
        throw ASRError.unsupportedMode
    }

    public func transcribeBatch(
        pcm: Data,
        sampleRate: Int,
        channels: Int,
        language: String,
        hotwords: [String]
    ) async throws -> RawTranscript {
        let started = Date()
        // 1) 包成 WAV。Whisper 服务端会自动重采样，但前端需要一个合法容器；
        //    16-bit / mono / 用户给的 sampleRate（默认 16k）就够了。
        let wav = WAVHeader.wrap(pcm: pcm, sampleRate: sampleRate, channels: channels)
        guard wav.count <= Self.maxUploadBytes else {
            throw ASRError.invalidAudio("超过 OpenAI Whisper 单次上限 25MB")
        }

        // 2) 构造 multipart/form-data 请求。
        let boundary = "openless-\(UUID().uuidString)"
        let url = baseURL.appendingPathComponent("audio/transcriptions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = makeMultipartBody(
            boundary: boundary,
            wav: wav,
            language: language,
            hotwords: hotwords
        )

        logger?("[whisper] POST \(url.absoluteString) bytes=\(body.count) lang=\(language) hot=\(hotwords.count)")

        // 3) 发送。upload(for:from:) 不会单独读 request.httpBody，所以 body 走第二个参数。
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, from: body)
        } catch {
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorTimedOut {
                throw ASRError.timeout
            }
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                throw ASRError.cancelled
            }
            throw ASRError.network(nsErr)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ASRError.network(NSError(
                domain: "CustomOpenAIWhisper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "非 HTTP 响应"]
            ))
        }

        // 4) HTTP 状态码 → ASRError。
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw ASRError.authFailed(statusCode: 401)
        case 413:
            throw ASRError.invalidAudio("audio too large")
        case 429:
            throw ASRError.quotaExceeded
        case 500...599:
            let message = parseErrorMessage(data: data) ?? "server error"
            throw ASRError.providerError(code: "http-\(http.statusCode)", message: message)
        default:
            let message = parseErrorMessage(data: data) ?? "HTTP \(http.statusCode)"
            throw ASRError.providerError(code: "http-\(http.statusCode)", message: message)
        }

        // 5) 解析 `{"text": "..."}`。
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw ASRError.providerError(
                code: "invalid-response",
                message: "Whisper 响应缺少 text 字段"
            )
        }

        let durationMs = Int(Date().timeIntervalSince(started) * 1000)
        return RawTranscript(text: text, durationMs: durationMs)
    }

    // MARK: - Multipart 构造

    /// 构造 multipart body。字段顺序与 OpenAI 官方示例一致：file → model → language → prompt。
    private func makeMultipartBody(
        boundary: String,
        wav: Data,
        language: String,
        hotwords: [String]
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"

        // file 字段
        body.appendUTF8("--\(boundary)\(crlf)")
        body.appendUTF8("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\(crlf)")
        body.appendUTF8("Content-Type: audio/wav\(crlf)\(crlf)")
        body.append(wav)
        body.appendUTF8(crlf)

        // model 字段
        body.appendUTF8("--\(boundary)\(crlf)")
        body.appendUTF8("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)")
        body.appendUTF8("\(model)\(crlf)")

        // language 字段（OpenAI 接收 ISO-639-1：zh / en / ja…；空字符串就不写让服务端自动检测）
        let lang = simplifyLanguage(language)
        if !lang.isEmpty {
            body.appendUTF8("--\(boundary)\(crlf)")
            body.appendUTF8("Content-Disposition: form-data; name=\"language\"\(crlf)\(crlf)")
            body.appendUTF8("\(lang)\(crlf)")
        }

        // prompt 字段：hotwords 拼接成逗号分隔字符串作为软提示。
        let cleaned = hotwords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !cleaned.isEmpty {
            let prompt = cleaned.joined(separator: ", ")
            body.appendUTF8("--\(boundary)\(crlf)")
            body.appendUTF8("Content-Disposition: form-data; name=\"prompt\"\(crlf)\(crlf)")
            body.appendUTF8("\(prompt)\(crlf)")
        }

        // 收尾 boundary
        body.appendUTF8("--\(boundary)--\(crlf)")
        return body
    }

    /// BCP-47 → ISO-639-1：`zh-CN` → `zh`，`en-US` → `en`，空 / 不识别返回空字符串
    /// （让 OpenAI 走自动检测）。
    private func simplifyLanguage(_ bcp47: String) -> String {
        let trimmed = bcp47.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return trimmed.split(separator: "-").first.map(String.init) ?? ""
    }

    /// 尝试从 OpenAI 风格的错误响应里挖 message：`{"error":{"message": "...", ...}}`。
    private func parseErrorMessage(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let err = json["error"] as? [String: Any], let m = err["message"] as? String {
            return m
        }
        if let m = json["message"] as? String { return m }
        return nil
    }
}

// MARK: - WAV 包装

/// 把 16-bit signed little-endian PCM 包成 RIFF/WAVE。
///
/// 仅支持 PCM（format code = 1）。`channels` / `sampleRate` 使用调用方给出的值，
/// bits-per-sample 锁死 16（OpenLessRecorder 的输出格式）。
enum WAVHeader {
    /// WAV header 长度：12 (RIFF) + 24 (fmt) + 8 (data prefix) = 44 字节。
    static let headerSize: Int = 44

    static func wrap(pcm: Data, sampleRate: Int, channels: Int) -> Data {
        let dataSize = UInt32(pcm.count)
        let bitsPerSample: UInt16 = 16
        let blockAlign: UInt16 = UInt16(channels) * bitsPerSample / 8
        let byteRate: UInt32 = UInt32(sampleRate) * UInt32(blockAlign)
        let chunkSize: UInt32 = 36 + dataSize

        var header = Data()
        // RIFF header
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46])      // "RIFF"
        header.append(uint32LE: chunkSize)
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45])      // "WAVE"

        // fmt chunk
        header.append(contentsOf: [0x66, 0x6d, 0x74, 0x20])      // "fmt "
        header.append(uint32LE: 16)                              // fmt chunk size = 16
        header.append(uint16LE: 1)                               // audio format = PCM
        header.append(uint16LE: UInt16(channels))
        header.append(uint32LE: UInt32(sampleRate))
        header.append(uint32LE: byteRate)
        header.append(uint16LE: blockAlign)
        header.append(uint16LE: bitsPerSample)

        // data chunk
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61])      // "data"
        header.append(uint32LE: dataSize)

        var wav = Data(capacity: header.count + pcm.count)
        wav.append(header)
        wav.append(pcm)
        return wav
    }
}

private extension Data {
    mutating func appendUTF8(_ s: String) {
        if let data = s.data(using: .utf8) {
            self.append(data)
        }
    }

    mutating func append(uint16LE value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }

    mutating func append(uint32LE value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
