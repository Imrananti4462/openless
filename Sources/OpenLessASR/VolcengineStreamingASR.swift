import Foundation
import OpenLessCore

public enum VolcengineASRError: Error, Sendable {
    case credentialsMissing
    case connectionFailed(String)
    case authenticationFailed
    case noFinalResult
    case decodeFailed(String)
}

public final class VolcengineStreamingASR: AudioConsumer, @unchecked Sendable {
    private let credentials: VolcengineCredentials
    private let logger: (@Sendable (String) -> Void)?
    private let dictionaryEntries: [DictionaryEntry]
    private let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
    private let targetAudioChunkBytes = 6_400 // 200ms of 16 kHz / 16-bit / mono PCM

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var pendingFinal: CheckedContinuation<RawTranscript, Error>?
    private var finalResult: RawTranscript?
    private var terminalError: Error?
    private var pendingAudio = Data()
    private var rawText: String = ""
    private let queue = DispatchQueue(label: "com.openless.asr")
    private var isConnected = false
    private var startTime: Date = Date()
    /// 火山 SAUC bigmodel 协议要求每一帧带正序号，最后一帧用负序号收尾。
    private var nextSequence: Int32 = 1
    private var bytesSentToServer: Int = 0
    private var framesSentToServer: Int = 0

    public init(
        credentials: VolcengineCredentials,
        dictionaryEntries: [DictionaryEntry] = [],
        logger: (@Sendable (String) -> Void)? = nil
    ) {
        self.credentials = credentials
        self.dictionaryEntries = dictionaryEntries
        self.logger = logger
    }

    public func openSession() async throws {
        let connectId = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.setValue(credentials.appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(credentials.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(credentials.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectId, forHTTPHeaderField: "X-Api-Connect-Id")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()
        isConnected = true
        startTime = Date()
        rawText = ""
        nextSequence = 1
        bytesSentToServer = 0
        framesSentToServer = 0
        queue.sync {
            pendingAudio.removeAll(keepingCapacity: true)
            finalResult = nil
            terminalError = nil
            pendingFinal = nil
        }

        // 发首帧 full client request（seq=1，positiveSequence）
        var requestPayload: [String: Any] = [
            "model_name": "bigmodel",
            "enable_itn": true,
            "enable_punc": true,
            "show_utterances": true,
        ]
        if let context = Self.hotwordContext(from: dictionaryEntries) {
            requestPayload["context"] = context
            logger?("[asr] hotwords injected: \(dictionaryEntries.filter { $0.enabled }.count)")
        }

        let payload: [String: Any] = [
            "user": ["uid": connectId],
            "audio": [
                "format": "pcm",
                "rate": 16000,
                "bits": 16,
                "channel": 1,
                "codec": "raw",
            ],
            "request": requestPayload,
        ]
        let json = try JSONSerialization.data(withJSONObject: payload)
        let firstSeq = nextSequence
        nextSequence += 1
        let frame = VolcengineFrame.build(
            messageType: .fullClientRequest,
            flags: .positiveSequence,
            serialization: .json,
            payload: json,
            sequence: firstSeq
        )
        try await task.send(.data(frame))

        // 启动接收循环
        receiveLoop(task: task)
    }

    public func consume(pcmChunk: Data) {
        queue.async { [weak self] in
            guard let self, self.isConnected, let task = self.task else { return }
            self.pendingAudio.append(pcmChunk)

            while self.pendingAudio.count >= self.targetAudioChunkBytes {
                let chunk = self.pendingAudio.prefix(self.targetAudioChunkBytes)
                self.pendingAudio.removeFirst(self.targetAudioChunkBytes)
                let seq = self.nextSequence
                self.nextSequence += 1
                let frame = VolcengineFrame.build(
                    messageType: .audioOnlyRequest,
                    flags: .positiveSequence,
                    serialization: .none,
                    payload: Data(chunk),
                    sequence: seq
                )
                self.bytesSentToServer += chunk.count
                self.framesSentToServer += 1
                task.send(.data(frame)) { err in
                    if let err = err {
                        // 把丢帧错误顶到日志里，定位"为什么服务端只收到 100ms"
                        self.logger?("[asr] audio frame seq=\(seq) send 失败: \(err.localizedDescription)")
                    }
                }
            }
        }
    }

    public func sendLastFrame() async throws {
        guard let task = task else { return }
        let leftover: Data? = queue.sync {
            guard !pendingAudio.isEmpty else { return nil }
            let data = pendingAudio
            pendingAudio.removeAll(keepingCapacity: true)
            return data
        }

        if let leftover {
            let seq = queue.sync { () -> Int32 in
                let s = nextSequence
                nextSequence += 1
                return s
            }
            let frame = VolcengineFrame.build(
                messageType: .audioOnlyRequest,
                flags: .positiveSequence,
                serialization: .none,
                payload: leftover,
                sequence: seq
            )
            try await task.send(.data(frame))
        }

        // 末帧用 negativeSequence + 负序号收尾，告诉服务端"流到此结束"。
        let finalSeq = queue.sync { () -> Int32 in
            let s = -nextSequence
            nextSequence += 1
            return s
        }
        let frame = VolcengineFrame.build(
            messageType: .audioOnlyRequest,
            flags: .negativeSequence,
            serialization: .none,
            payload: Data(),
            sequence: finalSeq
        )
        try await task.send(.data(frame))
        let totalBytes = queue.sync { bytesSentToServer }
        let totalFrames = queue.sync { framesSentToServer }
        // 16 kHz / 16-bit / mono → 32000 bytes/sec
        let durationMs = Int(Double(totalBytes) / 32.0)
        logger?("[asr] 发送总结：\(totalFrames) audio frames, \(totalBytes) bytes (~\(durationMs) ms)")
    }

    public func awaitFinalResult() async throws -> RawTranscript {
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                if let finalResult = self.finalResult {
                    self.finalResult = nil
                    continuation.resume(returning: finalResult)
                } else if let terminalError = self.terminalError {
                    self.terminalError = nil
                    continuation.resume(throwing: terminalError)
                } else {
                    self.pendingFinal = continuation
                }
            }
        }
    }

    public func cancel() {
        isConnected = false
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        complete(throwing: VolcengineASRError.noFinalResult)
    }

    private func receiveLoop(task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.complete(throwing: VolcengineASRError.connectionFailed(error.localizedDescription))
            case .success(let message):
                if case .data(let data) = message {
                    self.handleFrame(data)
                }
                if self.isConnected {
                    self.receiveLoop(task: task)
                }
            }
        }
    }

    private func handleFrame(_ data: Data) {
        guard let parsed = VolcengineFrame.parse(data) else {
            logger?("[asr] 帧解析失败 raw=\(data.prefix(32).map { String(format: "%02x", $0) }.joined())")
            return
        }

        if parsed.messageType == .errorMessage {
            let message = String(data: parsed.payload, encoding: .utf8) ?? "server error"
            logger?("[asr] error frame code=\(parsed.errorCode ?? 0) body=\(message.prefix(200))")
            complete(throwing: VolcengineASRError.connectionFailed("ASR error \(parsed.errorCode ?? 0): \(message)"))
            isConnected = false
            return
        }

        guard parsed.messageType == .fullServerResponse else { return }
        if let payloadStr = String(data: parsed.payload, encoding: .utf8) {
            logger?("[asr] server JSON: \(payloadStr.prefix(400))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: parsed.payload) as? [String: Any] else { return }
        guard let result = normalizedResult(from: json) else { return }

        // 流结束信号只信帧头 flags（lastPacket / negativeSequence）。
        // 之前误把 utterance.definite=true 当成流结束——但那只代表"这一段语音已固化"，
        // 用户可能还在继续说。结果一收到第一个 definite=true 就关掉接收，
        // 后面用户讲的内容全部丢失（实测丢了 9 秒）。
        let hasFinal = parsed.isFinal
        var fullText = (result["text"] as? String) ?? ""

        if let utterances = result["utterances"] as? [[String: Any]] {
            // 优先用 utterances 拼接的文本（包含全部分段，不论 definite 与否）
            let pieces = utterances.compactMap { $0["text"] as? String }
            if !pieces.isEmpty { fullText = pieces.joined() }
        }

        rawText = fullText

        if hasFinal {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let transcript = RawTranscript(text: fullText, durationMs: durationMs)
            complete(returning: transcript)
            isConnected = false
        }
    }

    private func complete(returning transcript: RawTranscript) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingAudio.removeAll(keepingCapacity: true)
            if let continuation = self.pendingFinal {
                self.pendingFinal = nil
                continuation.resume(returning: transcript)
            } else {
                self.finalResult = transcript
            }
        }
    }

    private func complete(throwing error: Error) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingAudio.removeAll(keepingCapacity: true)
            if let continuation = self.pendingFinal {
                self.pendingFinal = nil
                continuation.resume(throwing: error)
            } else {
                self.terminalError = error
            }
        }
    }

    private func normalizedResult(from json: [String: Any]) -> [String: Any]? {
        if let result = json["result"] as? [String: Any] {
            return result
        }
        if let results = json["result"] as? [[String: Any]], let first = results.first {
            return first
        }
        if let text = json["text"] as? String {
            return ["text": text]
        }
        return nil
    }

    private static func hotwordContext(from entries: [DictionaryEntry]) -> String? {
        let words = entries
            .filter { $0.enabled && !$0.trimmedPhrase.isEmpty }
            .map { $0.trimmedPhrase }
            .reduce(into: [String]()) { result, word in
                if !result.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                    result.append(word)
                }
            }
            .prefix(80)
            .map { ["word": $0] }

        guard !words.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: ["hotwords": Array(words)]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
