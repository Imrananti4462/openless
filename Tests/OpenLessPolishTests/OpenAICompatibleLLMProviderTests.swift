import XCTest
import OpenLessCore
@testable import OpenLessPolish

/// OpenAICompatibleLLMProvider 的单元测试。
///
/// 用一个自定义的 URLProtocol 子类拦截 URLSession 的请求，把它们转给一个
/// `RequestHandler` 闭包，由各个测试用例自己决定返回什么 HTTP 响应。
/// 这样不需要真实网络，也不需要 mock framework。
final class OpenAICompatibleLLMProviderTests: XCTestCase {

    // MARK: - 测试夹具

    /// 拦截 URLSession 流量的协议；所有 URLSessionConfiguration.ephemeral 走它。
    /// 注意：URLProtocol 子类必须是 NSObject 子类，且静态状态访问按 XCTest 串行假设处理。
    final class MockURLProtocol: URLProtocol {
        // 静态闭包：每个测试自己塞处理函数。XCTest 串行跑用例，单一句柄足够。
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        static var capturedRequests: [URLRequest] = []
        static var capturedBodies: [Data] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            // URLProtocol 不会自动把 httpBodyStream 露给我们，需要手动读。
            // URLSession 在用 .data(for:) 时会把 body 转成 stream，所以这里两条都试。
            var captured = request
            if let stream = request.httpBodyStream {
                captured.httpBody = Self.readAll(stream: stream)
            }
            Self.capturedRequests.append(captured)
            if let body = captured.httpBody {
                Self.capturedBodies.append(body)
            }

            guard let handler = Self.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(captured)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}

        private static func readAll(stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            return data
        }

        static func reset() {
            requestHandler = nil
            capturedRequests = []
            capturedBodies = []
        }
    }

    private func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: cfg)
    }

    private func makeConfig(
        apiKey: String = "SECRET_TEST_KEY_12345",
        model: String = "test-model",
        baseURL: URL = URL(string: "https://api.example.com/v1")!,
        extraHeaders: [String: String] = [:],
        temperature: Double = 0.3
    ) -> OpenAICompatibleConfig {
        OpenAICompatibleConfig(
            providerId: "test-provider",
            displayName: "Test Provider",
            baseURL: baseURL,
            apiKey: apiKey,
            model: model,
            extraHeaders: extraHeaders,
            temperature: temperature
        )
    }

    /// 标准成功响应（content = polished）。
    private func okResponse(content: String, url: URL) -> (HTTPURLResponse, Data) {
        let payload: [String: Any] = [
            "id": "chatcmpl-1",
            "object": "chat.completion",
            "choices": [
                ["index": 0, "message": ["role": "assistant", "content": content], "finish_reason": "stop"]
            ],
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (response, data)
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - 用例

    func test_polish_sends_correct_request_body() async throws {
        let config = makeConfig(model: "claude-test", temperature: 0.42)
        let provider = OpenAICompatibleLLMProvider(config: config, session: makeSession())

        MockURLProtocol.requestHandler = { req in
            self.okResponse(content: "polished", url: req.url!)
        }

        _ = try await provider.polish(rawText: "嗯就是那个 hello", mode: .light, hotwords: [])

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
        let body = try XCTUnwrap(MockURLProtocol.capturedBodies.first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "claude-test")
        XCTAssertEqual(json["temperature"] as? Double, 0.42)
        XCTAssertEqual(json["stream"] as? Bool, false)

        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[1]["role"], "user")

        // 不应出现非 OpenAI 协议的私有字段。
        let knownKeys: Set<String> = ["model", "temperature", "stream", "messages"]
        let actualKeys = Set(json.keys)
        XCTAssertEqual(actualKeys, knownKeys, "请求 body 出现了未预期字段：\(actualKeys.subtracting(knownKeys))")
    }

    func test_polish_sends_bearer_auth_header() async throws {
        let secret = "SECRET_TEST_KEY_12345"
        let config = makeConfig(apiKey: secret)
        let provider = OpenAICompatibleLLMProvider(config: config, session: makeSession())

        MockURLProtocol.requestHandler = { req in
            self.okResponse(content: "polished", url: req.url!)
        }

        _ = try await provider.polish(rawText: "hi", mode: .raw, hotwords: [])

        let req = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer \(secret)")

        // apiKey 不能出现在 URL 上。
        let urlString = req.url?.absoluteString ?? ""
        XCTAssertFalse(urlString.contains(secret), "apiKey 不能出现在 URL 中")

        // apiKey 不能出现在 body 里。
        let body = try XCTUnwrap(MockURLProtocol.capturedBodies.first)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertFalse(bodyString.contains(secret), "apiKey 不能出现在 body 中")
    }

    func test_polish_each_mode_uses_correct_prompts() async throws {
        for mode in PolishMode.allCases {
            MockURLProtocol.reset()
            let provider = OpenAICompatibleLLMProvider(config: makeConfig(), session: makeSession())

            MockURLProtocol.requestHandler = { req in
                self.okResponse(content: "p", url: req.url!)
            }

            _ = try await provider.polish(rawText: "测试原文 ABC", mode: mode, hotwords: [])

            let body = try XCTUnwrap(MockURLProtocol.capturedBodies.first)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])

            // System prompt 应等同于（或包含）PolishPrompts 给出的当前 mode 内容。
            let expectedSystem = PolishPrompts.systemPrompt(for: mode)
            let actualSystem = messages[0]["content"] ?? ""
            XCTAssertTrue(
                actualSystem.contains(expectedSystem),
                "mode=\(mode) 的 system prompt 应包含 PolishPrompts.systemPrompt(for:) 的输出"
            )

            // User prompt 应包含原始转写文本和 PolishPrompts.userPrompt 的标记。
            let actualUser = messages[1]["content"] ?? ""
            XCTAssertTrue(actualUser.contains("测试原文 ABC"))
            XCTAssertTrue(actualUser.contains("<raw_transcript>"))
        }
    }

    func test_polish_returns_assistant_message() async throws {
        let provider = OpenAICompatibleLLMProvider(config: makeConfig(), session: makeSession())

        MockURLProtocol.requestHandler = { req in
            self.okResponse(content: "整理后的最终输出。", url: req.url!)
        }

        let result = try await provider.polish(rawText: "原始", mode: .light, hotwords: [])
        XCTAssertEqual(result, "整理后的最终输出。")
    }

    func test_polish_throws_on_4xx() async throws {
        let provider = OpenAICompatibleLLMProvider(config: makeConfig(), session: makeSession())

        MockURLProtocol.requestHandler = { req in
            let body = "{\"error\":\"unauthorized\"}".data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, body)
        }

        do {
            _ = try await provider.polish(rawText: "x", mode: .raw, hotwords: [])
            XCTFail("期望抛 LLMError.invalidResponse(401)")
        } catch let error as LLMError {
            guard case .invalidResponse(let code, _) = error else {
                XCTFail("错误类型不对：\(error)"); return
            }
            XCTAssertEqual(code, 401)
        }
    }

    func test_polish_throws_on_5xx() async throws {
        let provider = OpenAICompatibleLLMProvider(config: makeConfig(), session: makeSession())

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("oops".utf8))
        }

        do {
            _ = try await provider.polish(rawText: "x", mode: .raw, hotwords: [])
            XCTFail("期望抛 LLMError.invalidResponse(503)")
        } catch let error as LLMError {
            guard case .invalidResponse(let code, _) = error else {
                XCTFail("错误类型不对：\(error)"); return
            }
            XCTAssertEqual(code, 503)
        }
    }

    func test_polish_throws_on_malformed_json() async throws {
        let provider = OpenAICompatibleLLMProvider(config: makeConfig(), session: makeSession())

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("not json {[".utf8))
        }

        do {
            _ = try await provider.polish(rawText: "x", mode: .raw, hotwords: [])
            XCTFail("期望抛 LLMError.parseError")
        } catch let error as LLMError {
            guard case .parseError = error else {
                XCTFail("错误类型不对：\(error)"); return
            }
        }
    }

    func test_polish_appends_hotwords_only_when_present() async throws {
        // ---- 空数组：system prompt 不应包含"热词"段 ----
        do {
            MockURLProtocol.reset()
            let provider = OpenAICompatibleLLMProvider(config: makeConfig(), session: makeSession())
            MockURLProtocol.requestHandler = { req in self.okResponse(content: "p", url: req.url!) }
            _ = try await provider.polish(rawText: "x", mode: .light, hotwords: [])

            let body = try XCTUnwrap(MockURLProtocol.capturedBodies.first)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            let system = messages[0]["content"] ?? ""
            XCTAssertFalse(system.contains("热词"), "无热词时 system 不应出现热词块")
        }

        // ---- 有热词：应出现热词块和具体词 ----
        do {
            MockURLProtocol.reset()
            let provider = OpenAICompatibleLLMProvider(config: makeConfig(), session: makeSession())
            MockURLProtocol.requestHandler = { req in self.okResponse(content: "p", url: req.url!) }
            _ = try await provider.polish(rawText: "x", mode: .light, hotwords: ["Claude", "OpenLess"])

            let body = try XCTUnwrap(MockURLProtocol.capturedBodies.first)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            let system = messages[0]["content"] ?? ""
            XCTAssertTrue(system.contains("热词"))
            XCTAssertTrue(system.contains("Claude"))
            XCTAssertTrue(system.contains("OpenLess"))
        }
    }

    func test_apikey_never_appears_in_logs() async throws {
        let secret = "SECRET_TEST_KEY_12345"

        // 用一个 actor-safe 容器收集 logger 输出，避免 Swift 6 严格并发下闭包捕获可变变量。
        let collector = LogCollector()
        let logger: @Sendable (String) -> Void = { line in collector.append(line) }

        let provider = OpenAICompatibleLLMProvider(
            config: makeConfig(apiKey: secret),
            session: makeSession(),
            logger: logger
        )

        MockURLProtocol.requestHandler = { req in
            // 故意把 secret 字符串塞回 body —— 真实场景里供应商不会这么干，
            // 但这能保护我们：哪怕将来不小心把 body 整体 echo 进日志，测试也能抓住。
            // 用 200 字符以内的占位，确保不会触发 body 截断让 secret 偶然落在边界外。
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"ok\"}}]}".data(using: .utf8)!)
        }

        _ = try await provider.polish(rawText: "原话", mode: .light, hotwords: [])

        let combined = collector.allLines().joined(separator: "\n")
        XCTAssertFalse(combined.isEmpty, "至少应有一条日志被记录")
        XCTAssertFalse(combined.contains(secret), "apiKey 字符串不能出现在任何日志输出中：\n\(combined)")
    }
}

// MARK: - 工具

/// 可在 @Sendable 闭包中写入的日志容器。用 NSLock 保证并发安全。
final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        lines.append(line)
    }

    func allLines() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return lines
    }
}
