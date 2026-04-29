import Foundation
import OpenLessCore

// AliyunParaformerASRProvider —— DashScope `paraformer-realtime-v2` 流式 ASR provider。
//
// 协议要点（详见 docs/plans/provider-abstraction.md §4.7）：
//   1. WS 连接到 wss://dashscope.aliyuncs.com/api-ws/v1/inference，header 带 Bearer apiKey。
//   2. 连上后立刻发**文本帧** `run-task`（JSON），等服务端 `task-started` 才能开始推音频。
//   3. 音频以**二进制帧**发送（PCM 原始字节，不要 base64）。
//   4. 用户停说时发**文本帧** `finish-task`，等 `task-finished` 拿全部 final 文本。
//   5. partial：每条 `result-generated` 事件都带 text；`sentence_end=true` 表示这一句已固化。
//      终态文本由所有 `sentence_end=true` 的 text 拼接而成；其余只走 partialResults。
//
// V1 限制（与 §4.7 对齐）：
//   - hotwords 必须先通过 vocabulary 上传 API 得到 vocabulary_id 才能注入；本期不做，
//     `supportsHotwords=false`。词典命中由 coordinator 后处理替换实现（已有逻辑）。
//   - DataInspection 默认 `enable`；隐私敏感用户可在 settings 显式关掉，但本 provider
//     不暴露这个开关，使用默认值。
//   - cancel 直接关 WS，不做 graceful drain（DashScope 协议没有 graceful cancel）。

public final class AliyunParaformerASRProvider: ASRProvider {
    public let info: ASRProviderInfo
    private let apiKey: String
    private let endpoint: URL
    private let model: String
    private let logger: (@Sendable (String) -> Void)?

    /// - Parameters:
    ///   - apiKey: DashScope Bearer token（与 LLM `aliyun-dashscope` 共享同一把 key）。
    ///   - endpoint: WS endpoint，默认国内站；测试或国际部署可覆盖。
    ///   - model: 默认 `paraformer-realtime-v2`，电话场景可换 `paraformer-realtime-8k-v2`。
    ///   - logger: 调试日志回调；libraries 不能直接落日志文件，由 caller 注入。
    public init(
        apiKey: String,
        endpoint: URL = URL(string: "wss://dashscope.aliyuncs.com/api-ws/v1/inference")!,
        model: String = "paraformer-realtime-v2",
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.logger = logger
        self.info = ASRProviderInfo(
            providerId: "aliyun-paraformer",
            displayName: "阿里通义 Paraformer",
            mode: .streaming,
            // vocabulary 注入暂不做，热词改走 coordinator 后处理 → 这里照实暴露 false。
            supportsHotwords: false,
            supportsLanguageHint: true,
            supportsPartialResults: true
        )
    }

    public func openStreamingSession(
        language: String,
        hotwords: [String]
    ) async throws -> ASRStreamingSession {
        let session = AliyunParaformerSession(
            apiKey: apiKey,
            endpoint: endpoint,
            model: model,
            language: language,
            logger: logger
        )
        try await session.open()
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
}

// MARK: - 流式 session

/// DashScope WebSocket 会话适配。
///
/// 线程模型：所有"内部状态"（partial 文本累积、final 句子列表、continuation、task_id）走
/// `NSLock` 同步——和 VolcengineStreamingSessionAdapter / AppleSpeechSession 一致，避免在 async
/// 上下文里暴露持锁路径触发 Swift 6 严格并发警告。
final class AliyunParaformerSession: ASRStreamingSession, @unchecked Sendable {
    let partialResults: AsyncStream<String>
    private let partialContinuation: AsyncStream<String>.Continuation

    private let apiKey: String
    private let endpoint: URL
    private let model: String
    private let language: String
    private let logger: (@Sendable (String) -> Void)?

    private let lock = NSLock()
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    /// 客户端生成的 task_id；run-task 与 finish-task 必须一致。
    private let taskId: String
    /// 拼接 final 文本：所有 `sentence_end=true` 的 result-generated.text 顺序 join。
    private var finalSentences: [String] = []
    /// 已收到 task-started 才能发音频；之前到达的 PCM 全部缓冲在 pendingAudio。
    private var taskStarted: Bool = false
    private var pendingAudio: [Data] = []
    /// awaitFinalResult 的 continuation；task-finished / 错误 / 关闭时 resume。
    private var finalContinuation: CheckedContinuation<RawTranscript, Error>?
    /// 终态：true 后任何 deliver 都被吞，避免 continuation 被重复 resume。
    private var didDeliverFinal: Bool = false
    /// 是否已发 finish-task，避免 endStream 多次调用重复发送。
    private var didSendFinish: Bool = false
    private var startedAt: Date = Date()

    init(
        apiKey: String,
        endpoint: URL,
        model: String,
        language: String,
        logger: (@Sendable (String) -> Void)?
    ) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
        self.language = language
        self.logger = logger
        self.taskId = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        self.session = URLSession(configuration: .default)
        var capturedContinuation: AsyncStream<String>.Continuation!
        self.partialResults = AsyncStream<String> { continuation in
            capturedContinuation = continuation
        }
        self.partialContinuation = capturedContinuation
    }

    // MARK: - 生命周期

    /// 建立 WebSocket，发 run-task，等 `task-started` 事件之后再返回。
    /// 在等待 task-started 期间到达的 PCM 都进 pendingAudio，task-started 后批量 flush。
    func open() async throws {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // 默认开启数据巡检；隐私敏感用户后续可通过 settings 切到 disable。
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-DataInspection")

        let task = session.webSocketTask(with: request)
        // 不在 async 上下文里直接持锁——下沉到同步辅助，避免 Swift 6 严格并发警告升级为 error。
        attachTask(task)
        task.resume()
        receiveLoop(task: task)

        // 发 run-task。
        let payload = makeRunTaskPayload()
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(data: data, encoding: .utf8) ?? ""
        do {
            try await task.send(.string(text))
            logger?("[aliyun-paraformer] run-task sent (taskId=\(taskId), model=\(model))")
        } catch {
            // 握手未通过 / 401 / 403 在 send 阶段会以 URLError 形式回流。
            await mapAndDeliverConnectError(error)
            throw mapURLError(error)
        }

        // 等 task-started（最多 10s）。这里用一个 polling 风格 await——
        // 避免给 session 再加一个独立 continuation，让代码路径单一。
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if isTaskStartedSnapshot() { return }
            if let err = takeTerminalErrorSnapshot() { throw err }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        // 超时——主动取消会话并抛 timeout。
        await cancel()
        throw ASRError.timeout
    }

    // MARK: - AudioConsumer

    func consume(pcmChunk: Data) {
        // 同步入口：根据 taskStarted 决定立即发还是入队。
        // URLSessionWebSocketTask.send(_:completionHandler:) 在底层并发队列异步执行，
        // 这里不能 await——直接调 completion handler 版本即可。
        lock.lock()
        let started = taskStarted
        let snapshotTask = task
        if !started {
            pendingAudio.append(pcmChunk)
        }
        lock.unlock()

        guard started, let snapshotTask else { return }
        snapshotTask.send(.data(pcmChunk)) { [weak self] err in
            if let err = err {
                self?.logger?("[aliyun-paraformer] audio send 失败: \(err.localizedDescription)")
            }
        }
    }

    // MARK: - ASRStreamingSession

    func sendAudio(_ pcm: Data) async throws {
        consume(pcmChunk: pcm)
    }

    func endStream() async throws {
        guard markFinishSent() else { return }
        let payload: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskId,
                "streaming": "duplex",
            ],
            "payload": [
                "input": [String: Any]()
            ],
        ]
        guard let task = currentTaskSnapshot(),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await task.send(.string(text))
            logger?("[aliyun-paraformer] finish-task sent")
        } catch {
            logger?("[aliyun-paraformer] finish-task send 失败: \(error.localizedDescription)")
            throw mapURLError(error)
        }
    }

    func awaitFinalResult() async throws -> RawTranscript {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RawTranscript, Error>) in
            // 注册前先看终态：可能 task-finished 已经在 receiveLoop 里到达且没有 awaiter。
            switch registerFinalContinuation(continuation) {
            case .registered:
                return
            case .alreadyDeliveredText(let text, let durationMs):
                continuation.resume(returning: RawTranscript(text: text, durationMs: durationMs))
            case .alreadyDeliveredError(let err):
                continuation.resume(throwing: err)
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
        logger?("[aliyun-paraformer] cancelled")
    }

    // MARK: - 内部

    private func makeRunTaskPayload() -> [String: Any] {
        // language_hints：从 BCP-47 抽出主语言代码（zh-CN → zh，en-US → en），
        // 默认还兜上 en 提高混说场景识别率。空 / 未识别 → 仅给 zh。
        let hints = languageHints(from: language)
        let parameters: [String: Any] = [
            "format": "pcm",
            "sample_rate": 16000,
            "language_hints": hints,
            "punctuation_prediction_enabled": true,
            "max_sentence_silence": 500,
            // 8k-v2 上 emo_tag 与 semantic_punctuation_enabled 互斥；这里用默认 16k v2 → 关掉
            // semantic_punctuation_enabled 即可，emo_tag 不需要。
            "semantic_punctuation_enabled": false,
            "heartbeat": false,
        ]
        // hotwords 注入需要 vocabulary_id（先上传词表才有），v1 不做——这里不放 vocabulary_id 字段。

        return [
            "header": [
                "action": "run-task",
                "task_id": taskId,
                "streaming": "duplex",
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": model,
                "parameters": parameters,
                "input": [String: Any](),
            ],
        ]
    }

    private func languageHints(from bcp47: String) -> [String] {
        let trimmed = bcp47.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ["zh", "en"] }
        let primary = trimmed.split(separator: "-").first.map(String.init)?.lowercased() ?? "zh"
        // DashScope paraformer-realtime-v2 接受的码：zh / en / ja / yue / ko / de / fr / ru / es / it / ar
        let known: Set<String> = ["zh", "en", "ja", "yue", "ko", "de", "fr", "ru", "es", "it", "ar"]
        if known.contains(primary) {
            // 中英混说默认值；其他主语言只挂自己。
            return primary == "zh" || primary == "en" ? ["zh", "en"] : [primary]
        }
        return ["zh", "en"]
    }

    /// 接收循环：解析 `task-started` / `result-generated` / `task-finished` / `task-failed`。
    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.handleConnectionError(error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleEvent(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.handleEvent(text)
                    }
                @unknown default:
                    break
                }
                if !self.isFinishedSnapshot() {
                    self.receiveLoop(task: task)
                }
            }
        }
    }

    private func handleEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = json["header"] as? [String: Any],
              let event = header["event"] as? String else {
            logger?("[aliyun-paraformer] unrecognized event: \(text.prefix(200))")
            return
        }
        switch event {
        case "task-started":
            logger?("[aliyun-paraformer] task-started")
            flushPendingOnTaskStarted()
        case "result-generated":
            handleResultGenerated(payload: json["payload"] as? [String: Any] ?? [:])
        case "task-finished":
            logger?("[aliyun-paraformer] task-finished")
            deliverFinalSuccess()
        case "task-failed":
            let code = (header["error_code"] as? String) ?? "unknown"
            let message = (header["error_message"] as? String) ?? "task-failed"
            logger?("[aliyun-paraformer] task-failed code=\(code) message=\(message)")
            deliverFinalFailure(.providerError(code: code, message: message))
        default:
            // 忽略心跳 / 其他暂未消费的事件。
            return
        }
    }

    private func handleResultGenerated(payload: [String: Any]) {
        // 标准 payload 形态：{ "output": { "sentence": { "text": "...", "sentence_end": true/false } } }
        let output = payload["output"] as? [String: Any] ?? [:]
        let sentence = output["sentence"] as? [String: Any] ?? [:]
        let text = (sentence["text"] as? String) ?? ""
        let sentenceEnd = (sentence["sentence_end"] as? Bool) ?? false
        if text.isEmpty { return }
        if sentenceEnd {
            appendFinalSentence(text)
        } else {
            partialContinuation.yield(text)
        }
    }

    private func handleConnectionError(_ error: Error) {
        // WS upgrade 阶段的 401 / 403 通过 URLError 流回；中间断连也走这里。
        // 只有终态没到时才升级成 final 错误，否则忽略。
        let mapped = mapURLError(error)
        if !isDeliveredSnapshot() {
            // 没正常 task-finished 就被中断 → 用 mapped 错误结束。
            deliverFinalFailure(mapped)
        }
    }

    /// 把 URLError → ASRError 映射，覆盖 401 / 403 / 超时 / 取消 / 其他网络错。
    private func mapURLError(_ error: Error) -> ASRError {
        let nsErr = error as NSError
        if nsErr.domain == NSURLErrorDomain {
            switch nsErr.code {
            case NSURLErrorUserAuthenticationRequired,
                 NSURLErrorUserCancelledAuthentication:
                return .authFailed(statusCode: 401)
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorCancelled:
                return .cancelled
            default:
                break
            }
        }
        // URLSessionWebSocketTask 把握手 HTTP 状态码暴露在 userInfo["_NSURLErrorHTTPResponseKey"]。
        if let response = nsErr.userInfo["_NSURLErrorFailingURLPeerTrustErrorKey"] as? HTTPURLResponse {
            return mapHTTPStatus(response.statusCode)
        }
        if let response = nsErr.userInfo["NSErrorFailingURLResponseKey"] as? HTTPURLResponse {
            return mapHTTPStatus(response.statusCode)
        }
        return .network(nsErr)
    }

    private func mapHTTPStatus(_ code: Int) -> ASRError {
        switch code {
        case 401: return .authFailed(statusCode: 401)
        case 403: return .quotaExceeded
        case 408: return .timeout
        case 429: return .quotaExceeded
        default:
            let nsErr = NSError(domain: "AliyunParaformer", code: code, userInfo: [
                NSLocalizedDescriptionKey: "WS upgrade failed (HTTP \(code))"
            ])
            return .network(nsErr)
        }
    }

    private func mapAndDeliverConnectError(_ error: Error) async {
        let mapped = mapURLError(error)
        deliverFinalFailure(mapped)
    }

    // MARK: - 同步辅助（持锁；不在 async 上下文里直接调用 NSLock）

    private func attachTask(_ newTask: URLSessionWebSocketTask) {
        lock.lock()
        defer { lock.unlock() }
        self.task = newTask
        self.startedAt = Date()
    }

    private func appendFinalSentence(_ text: String) {
        lock.lock()
        finalSentences.append(text)
        lock.unlock()
        // partial 也 yield 一份："这一句已固化"对 UI 来说也是个有效中间态。
        partialContinuation.yield(text)
    }

    private func flushPendingOnTaskStarted() {
        var pending: [Data] = []
        var snapshotTask: URLSessionWebSocketTask?
        lock.lock()
        taskStarted = true
        pending = pendingAudio
        pendingAudio.removeAll(keepingCapacity: false)
        snapshotTask = task
        lock.unlock()

        guard let snapshotTask else { return }
        for chunk in pending {
            snapshotTask.send(.data(chunk)) { [weak self] err in
                if let err = err {
                    self?.logger?("[aliyun-paraformer] flush audio 失败: \(err.localizedDescription)")
                }
            }
        }
    }

    private func isTaskStartedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return taskStarted
    }

    private func isFinishedSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didDeliverFinal
    }

    private func isDeliveredSnapshot() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return didDeliverFinal
    }

    private func currentTaskSnapshot() -> URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }

    private func markFinishSent() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if didSendFinish { return false }
        didSendFinish = true
        return true
    }

    /// 暂存的终态错误：在 open() 等待 task-started 阶段，receiveLoop 已经收到 task-failed
    /// 等致命事件时，把错误暴露给 open 让它直接抛。
    private func takeTerminalErrorSnapshot() -> ASRError? {
        lock.lock()
        defer { lock.unlock() }
        guard didDeliverFinal else { return nil }
        // 已 deliver 但 finalContinuation 还没注册——错误在 cont 里已经投递；
        // open 路径直接返回一个语义合理的错误。
        return .providerError(code: "task-failed", message: "DashScope 拒绝任务（详见日志）")
    }

    private enum FinalContinuationOutcome {
        case registered
        case alreadyDeliveredText(String, Int)
        case alreadyDeliveredError(Error)
    }

    private func registerFinalContinuation(
        _ continuation: CheckedContinuation<RawTranscript, Error>
    ) -> FinalContinuationOutcome {
        lock.lock()
        defer { lock.unlock() }
        if didDeliverFinal {
            // 终态已到：要么是文本（task-finished 拼好的），要么是错误。
            if let err = pendingFinalError {
                pendingFinalError = nil
                return .alreadyDeliveredError(err)
            }
            let text = finalSentences.joined()
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            return .alreadyDeliveredText(text, durationMs)
        }
        finalContinuation = continuation
        return .registered
    }

    private struct CancelSnapshot {
        let task: URLSessionWebSocketTask?
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

    /// 已 deliver 终态但 awaitFinalResult 还没注册时暂存错误，等注册时再投递。
    private var pendingFinalError: Error?

    private func deliverFinalSuccess() {
        var cont: CheckedContinuation<RawTranscript, Error>?
        var text = ""
        var durationMs = 0
        lock.lock()
        if didDeliverFinal {
            lock.unlock()
            return
        }
        didDeliverFinal = true
        cont = finalContinuation
        finalContinuation = nil
        text = finalSentences.joined()
        durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        lock.unlock()
        partialContinuation.finish()
        cont?.resume(returning: RawTranscript(text: text, durationMs: durationMs))
        logger?("[aliyun-paraformer] final delivered (len=\(text.count))")
    }

    private func deliverFinalFailure(_ error: ASRError) {
        var cont: CheckedContinuation<RawTranscript, Error>?
        lock.lock()
        if didDeliverFinal {
            lock.unlock()
            return
        }
        didDeliverFinal = true
        cont = finalContinuation
        finalContinuation = nil
        if cont == nil {
            pendingFinalError = error
        }
        lock.unlock()
        partialContinuation.finish()
        cont?.resume(throwing: error)
        logger?("[aliyun-paraformer] final error: \(error)")
    }
}
