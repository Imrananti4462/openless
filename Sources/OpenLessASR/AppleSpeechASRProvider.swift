import AVFoundation
import Foundation
import Speech
import OpenLessCore

// AppleSpeechASRProvider 把 macOS 内置 `SFSpeechRecognizer` 包装成 `ASRProvider`。
//
// 为什么单独一个 provider 而不是共用火山那一套：
//   - Apple Speech 不走 WebSocket / HTTP，是系统 SDK；audio 通过 AVAudioPCMBuffer 直接 append
//     到 SFSpeechAudioBufferRecognitionRequest，没有 framing / gzip。
//   - 不需要任何 apiKey / endpoint 配置；权限走 TCC（NSSpeechRecognitionUsageDescription）。
//   - 在 Apple Silicon 上 zh-CN 支持 on-device，能彻底离线；Intel / 老机器降级走 Apple 云端。
//
// V1 限制（接受）：
//   - 一个 session 一个 SFSpeechRecognitionTask，不做长时段轮换。Apple 的 ~60 秒软上限可能让
//     超长录音失败；这里不处理，先把"切到 Apple Speech 能识别"的主路径打通。
//   - `transcribeBatch` 抛 `.unsupportedMode`——Apple Speech 的批量入口（SFSpeechURLRecognitionRequest）
//     在 M1 没用到，先不实现。
//   - hotwords 通过 `contextualStrings` 喂给 recognizer，Apple 文档建议总长不超过 100 条。

public final class AppleSpeechASRProvider: ASRProvider {
    public let info: ASRProviderInfo
    private let logger: (@Sendable (String) -> Void)?

    public init(logger: (@Sendable (String) -> Void)? = nil) {
        self.logger = logger
        self.info = ASRProviderInfo(
            providerId: "apple-speech",
            displayName: "macOS 本地 (Apple Speech)",
            mode: .streaming,
            supportsHotwords: true,
            supportsLanguageHint: true,
            supportsPartialResults: true
        )
    }

    public func openStreamingSession(
        language: String,
        hotwords: [String]
    ) async throws -> ASRStreamingSession {
        // 1) 鉴权——SFSpeechRecognizer 需要先经过 requestAuthorization。
        //    notDetermined / denied / restricted 全部视为"用不了"——抛 authFailed 让上层走 mock。
        let auth = await Self.requestAuthorization()
        guard auth == .authorized else {
            logger?("[apple-speech] authorization not granted: \(auth.rawValue)")
            throw ASRError.authFailed(statusCode: nil)
        }

        // 2) 构造 recognizer。指定 language 解不出来时回退到 zh-CN（同时也兜住空字符串）。
        let locale = Locale(identifier: language.isEmpty ? "zh-CN" : language)
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            logger?("[apple-speech] no recognizer for locale=\(locale.identifier)")
            throw ASRError.providerError(code: "unavailable", message: "Apple Speech 不支持 locale \(locale.identifier)")
        }
        guard recognizer.isAvailable else {
            logger?("[apple-speech] recognizer.isAvailable=false")
            throw ASRError.providerError(code: "unavailable", message: "Apple Speech 当前不可用（系统忙或未联网）")
        }

        // 3) 构造请求。on-device 优先；不支持 on-device 的机器自动回退到 Apple 云端，不硬失败。
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        // macOS 13+：让识别结果自带标点。低版本属性不存在，但项目最低 15.0 不会触发。
        request.addsPunctuation = true
        // contextualStrings 即"提示词"——Apple 文档建议 ≤100 条；多余的截掉。
        let cleanHotwords = hotwords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        request.contextualStrings = Array(cleanHotwords.prefix(100))

        let session = AppleSpeechSession(
            recognizer: recognizer,
            request: request,
            onDevice: recognizer.supportsOnDeviceRecognition,
            logger: logger
        )
        try session.startTask()
        logger?("[apple-speech] streaming session opened (locale=\(locale.identifier), onDevice=\(recognizer.supportsOnDeviceRecognition), hotwords=\(request.contextualStrings.count))")
        return session
    }

    public func transcribeBatch(
        pcm: Data,
        sampleRate: Int,
        channels: Int,
        language: String,
        hotwords: [String]
    ) async throws -> RawTranscript {
        throw ASRError.unsupportedMode
    }

    /// 把 SFSpeechRecognizer.requestAuthorization 的 callback 包成 async。
    /// 同一个进程内多次调用是安全的——Apple 内部缓存了授权状态。
    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

/// 适配 Apple Speech 到 `ASRStreamingSession`。
///
/// - 录音输出是 16 kHz / Int16 / mono / interleaved 的 `Data`。
/// - SFSpeechAudioBufferRecognitionRequest 接 `AVAudioPCMBuffer`；我们就地把 Int16 → Float32。
///   保持 16 kHz / mono：Apple 的 recognizer 在低采样率上工作良好，不需要再升 24kHz/44.1kHz。
final class AppleSpeechSession: ASRStreamingSession, @unchecked Sendable {
    let partialResults: AsyncStream<String>
    private let partialContinuation: AsyncStream<String>.Continuation

    private let recognizer: SFSpeechRecognizer
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let onDevice: Bool
    private let logger: (@Sendable (String) -> Void)?

    /// 录音的 PCM 格式：16 kHz / Int16 / mono。
    private let inputSampleRate: Double = 16_000
    /// 转给 Apple 的 PCM 格式：16 kHz / Float32 / mono；同采样率不需要 resample。
    private let bufferFormat: AVAudioFormat

    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?
    /// 最终 transcript continuation——`awaitFinalResult()` 阻塞在这上面，
    /// 由 SFSpeechRecognitionTask 的 result handler 在 `result.isFinal=true` 或 error 到达时唤醒。
    private var finalContinuation: CheckedContinuation<RawTranscript, Error>?
    private var didDeliverFinal = false
    private var didEndAudio = false
    private var startedAt: Date = Date()

    init(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onDevice: Bool,
        logger: (@Sendable (String) -> Void)?
    ) {
        self.recognizer = recognizer
        self.request = request
        self.onDevice = onDevice
        self.logger = logger
        // 16 kHz Float32 mono——和录音同采样率，避免重采样链路。
        // 强制成 non-optional：参数都是合法值，AVAudioFormat 不会失败。
        self.bufferFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        var capturedContinuation: AsyncStream<String>.Continuation!
        self.partialResults = AsyncStream<String> { continuation in
            capturedContinuation = continuation
        }
        self.partialContinuation = capturedContinuation
    }

    /// 启动 SFSpeechRecognitionTask。失败时把 ASRError 抛出来，让 provider 路径降级。
    func startTask() throws {
        lock.lock()
        defer { lock.unlock() }
        startedAt = Date()
        // recognitionTask(with:resultHandler:) 实际上不会抛错（错误从 handler 走），
        // 这里 try 仅用于符合 protocol；如果未来 Apple 改了 API 也好定位。
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleResult(result, error: error)
        }
        self.task = task
    }

    // MARK: - AudioConsumer

    func consume(pcmChunk: Data) {
        appendPCM(pcmChunk)
    }

    // MARK: - ASRStreamingSession

    func sendAudio(_ pcm: Data) async throws {
        appendPCM(pcm)
    }

    func endStream() async throws {
        // 把 lock 操作下沉到同步辅助方法，避免 async 上下文里直接持锁
        // （Swift 6 严格并发模式会把这种用法升级为 error）。
        guard markEndAudio() else { return }
        request.endAudio()
        logger?("[apple-speech] endAudio()")
    }

    func awaitFinalResult() async throws -> RawTranscript {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RawTranscript, Error>) in
            // continuation 注册走同步辅助：拿到 .registered 才让它挂在 finalContinuation 上；
            // 拿到 .alreadyDelivered 时直接抛 timeout（理论上不会触发）。
            switch registerFinalContinuation(continuation) {
            case .registered:
                return
            case .alreadyDelivered:
                continuation.resume(throwing: ASRError.timeout)
            }
        }
    }

    func cancel() async {
        let snapshot = takeStateForCancel()
        snapshot.task?.cancel()
        partialContinuation.finish()
        if !snapshot.alreadyDelivered {
            snapshot.cont?.resume(throwing: ASRError.cancelled)
        }
        logger?("[apple-speech] cancelled")
    }

    // MARK: - 同步辅助（持锁；不在 async 上下文里直接调用 NSLock）

    /// 标记 endAudio 已调用。返回 true 表示这是首次标记（外层应实际调用 endAudio）。
    private func markEndAudio() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didEndAudio { return false }
        didEndAudio = true
        return true
    }

    private enum FinalContinuationOutcome {
        case registered
        case alreadyDelivered
    }

    private func registerFinalContinuation(
        _ continuation: CheckedContinuation<RawTranscript, Error>
    ) -> FinalContinuationOutcome {
        lock.lock()
        defer { lock.unlock() }
        if didDeliverFinal {
            return .alreadyDelivered
        }
        finalContinuation = continuation
        return .registered
    }

    private struct CancelSnapshot {
        let task: SFSpeechRecognitionTask?
        let cont: CheckedContinuation<RawTranscript, Error>?
        let alreadyDelivered: Bool
    }

    private func takeStateForCancel() -> CancelSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = CancelSnapshot(
            task: task,
            cont: finalContinuation,
            alreadyDelivered: didDeliverFinal
        )
        task = nil
        finalContinuation = nil
        didDeliverFinal = true
        return snapshot
    }

    // MARK: - 内部

    /// 把 16 kHz Int16 mono `Data` 转成 AVAudioPCMBuffer（Float32）→ request.append(buffer)。
    /// 容错：长度不是 2 的倍数 / 空数据 → 静默丢弃。
    private func appendPCM(_ pcm: Data) {
        guard !pcm.isEmpty else { return }
        let int16Count = pcm.count / MemoryLayout<Int16>.size
        guard int16Count > 0 else { return }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: AVAudioFrameCount(int16Count)) else {
            return
        }
        buffer.frameLength = AVAudioFrameCount(int16Count)
        guard let floatChannel = buffer.floatChannelData?[0] else { return }

        // Int16 → Float32：除以 32768，得到 [-1, 1) 的范围。
        pcm.withUnsafeBytes { rawBuffer -> Void in
            guard let baseAddr = rawBuffer.baseAddress else { return }
            let int16Ptr = baseAddr.assumingMemoryBound(to: Int16.self)
            let scale: Float = 1.0 / 32768.0
            for i in 0..<int16Count {
                floatChannel[i] = Float(int16Ptr[i]) * scale
            }
        }

        request.append(buffer)
    }

    /// SFSpeechRecognitionTask 的 result handler 回调入口。
    /// - 流式 partial：yield 到 partialResults。
    /// - final（result.isFinal=true）：填 finalContinuation。
    /// - error：填 finalContinuation 抛错。
    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let text = result.bestTranscription.formattedString
            if !result.isFinal {
                if !text.isEmpty {
                    partialContinuation.yield(text)
                }
                return
            }
            // Final
            deliverFinal(.success(makeTranscript(from: text)))
            return
        }
        if let error {
            // SFSpeech 偶尔在 task cancel 时把 cancel 包成 error 推回来——映射成 cancelled。
            let nsErr = error as NSError
            let mapped: ASRError
            if nsErr.domain == "kAFAssistantErrorDomain" || nsErr.code == 203 || nsErr.code == 1 {
                // 不同 macOS 版本错误码不一致；这里把"无识别结果 / no speech detected"等
                // 业务错误统一包到 providerError，让 coordinator 当一次失败处理。
                mapped = .providerError(code: "speech-error-\(nsErr.code)", message: nsErr.localizedDescription)
            } else {
                mapped = .network(nsErr)
            }
            deliverFinal(.failure(mapped))
        }
    }

    private func makeTranscript(from text: String) -> RawTranscript {
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        return RawTranscript(text: text, durationMs: durationMs)
    }

    private func deliverFinal(_ outcome: Result<RawTranscript, Error>) {
        lock.lock()
        if didDeliverFinal {
            lock.unlock()
            return
        }
        didDeliverFinal = true
        let cont = finalContinuation
        finalContinuation = nil
        lock.unlock()
        partialContinuation.finish()
        switch outcome {
        case .success(let transcript):
            cont?.resume(returning: transcript)
            logger?("[apple-speech] final delivered (len=\(transcript.text.count))")
        case .failure(let error):
            cont?.resume(throwing: error)
            logger?("[apple-speech] final error: \(error)")
        }
    }
}
