import Foundation
import Testing

@testable import AIKit

/// SSE 报文取自两家的接口文档，不是脑补的格式。
@Suite("Provider 协议解码")
struct ProviderTests {

    // MARK: - Anthropic

    /// 一次完整的 Anthropic 流式响应。
    static let anthropicStream = """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5","usage":{"input_tokens":25,"output_tokens":1}}}

        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

        event: ping
        data: {"type":"ping"}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"fix: "}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"修复登录超时"}}

        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":12}}

        event: message_stop
        data: {"type":"message_stop"}

        """

    @Test("Anthropic 流式文本与用量")
    func anthropicStreamDecoding() async throws {
        let session = StubURLProtocol.makeSession(sse: Self.anthropicStream)
        let provider = AnthropicProvider(apiKey: "sk-test", session: session)

        var text = ""
        var usage: AIUsage?
        for try await event in provider.stream(
            AIRequest(model: "claude-opus-5", messages: [.user("写个提交信息")]))
        {
            switch event {
            case let .textDelta(delta): text += delta
            case let .completed(reported): usage = reported
            }
        }

        #expect(text == "fix: 修复登录超时")
        #expect(usage == AIUsage(inputTokens: 25, outputTokens: 12))
    }

    @Test("Anthropic 请求头与报文")
    func anthropicRequestShape() async throws {
        let session = StubURLProtocol.makeSession(sse: Self.anthropicStream)
        let provider = AnthropicProvider(apiKey: "sk-test", session: session)

        _ = try await provider.complete(
            AIRequest(model: "claude-opus-5", system: "你是中文助手", messages: [.user("嗨")]))

        let (request, body) = StubURLProtocol.recordedRequest(for: session)
        let recorded = try #require(request)

        #expect(recorded.url?.path == "/v1/messages")
        #expect(recorded.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        // 契约版本号必须带，否则接口直接拒绝
        #expect(recorded.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        // 不该出现 OpenAI 那套认证头
        #expect(recorded.value(forHTTPHeaderField: "authorization") == nil)

        // #require 不能嵌套，先各自落成变量
        let bodyData = try #require(body)
        let decoded = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        let json = try #require(decoded)
        // Anthropic 的 system 在顶层，不在 messages 里
        #expect(json["system"] as? String == "你是中文助手")
        #expect(json["stream"] as? Bool == true)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] == "user")
    }

    @Test("丢弃 thinking 增量，只保留正文")
    func anthropicIgnoresThinkingDeltas() async throws {
        // 混进来的话，模型的思考过程会被直接写进提交框
        let session = StubURLProtocol.makeSession(
            sse: """
                event: content_block_delta
                data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"让我想想改了什么"}}

                event: content_block_delta
                data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"feat: 新增导出"}}

                event: message_stop
                data: {"type":"message_stop"}

                """)

        let provider = AnthropicProvider(apiKey: "sk-test", session: session)
        let text = try await provider.complete(
            AIRequest(model: "claude-opus-5", messages: [.user("x")]))

        #expect(text == "feat: 新增导出")
    }

    @Test("拒绝回答时报错而不是静默返回空")
    func anthropicSurfacesRefusal() async throws {
        let session = StubURLProtocol.makeSession(
            sse: """
                event: message_delta
                data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":0}}

                """)

        let provider = AnthropicProvider(apiKey: "sk-test", session: session)

        await #expect(throws: AIError.self) {
            _ = try await provider.complete(AIRequest(model: "claude-opus-5", messages: [.user("x")]))
        }
    }

    // MARK: - OpenAI 兼容

    static let openAIStream = """
        data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}

        data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"docs: "}}]}

        data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"补充部署说明"}}]}

        data: {"id":"c1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

        data: [DONE]

        """

    @Test("OpenAI 兼容流式文本")
    func openAIStreamDecoding() async throws {
        let session = StubURLProtocol.makeSession(sse: Self.openAIStream)
        let provider = OpenAICompatibleProvider(apiKey: "sk-test", session: session)

        let text = try await provider.complete(
            AIRequest(model: "gpt-5", messages: [.user("写个提交信息")]))

        #expect(text == "docs: 补充部署说明")
    }

    @Test("OpenAI 兼容请求头与报文")
    func openAIRequestShape() async throws {
        let session = StubURLProtocol.makeSession(sse: Self.openAIStream)
        let provider = OpenAICompatibleProvider(
            apiKey: "sk-test",
            baseURL: .literal("https://api.deepseek.com/v1"),
            session: session
        )

        _ = try await provider.complete(
            AIRequest(model: "deepseek-chat", system: "你是中文助手", messages: [.user("嗨")]))

        let (request, body) = StubURLProtocol.recordedRequest(for: session)
        let recorded = try #require(request)

        #expect(recorded.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        #expect(recorded.value(forHTTPHeaderField: "authorization") == "Bearer sk-test")
        #expect(recorded.value(forHTTPHeaderField: "x-api-key") == nil)

        let bodyData = try #require(body)
        let decoded = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        let json = try #require(decoded)
        // 这套协议里 system 是 messages 的第一条
        #expect(json["system"] == nil)
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] == "system")
        #expect(messages[0]["content"] == "你是中文助手")
        #expect(messages[1]["role"] == "user")
    }

    @Test("带 usage 的最终块")
    func openAIReportsUsageWhenPresent() async throws {
        let session = StubURLProtocol.makeSession(
            sse: """
                data: {"choices":[{"delta":{"content":"ok"}}]}

                data: {"choices":[],"usage":{"prompt_tokens":30,"completion_tokens":5}}

                data: [DONE]

                """)

        let provider = OpenAICompatibleProvider(apiKey: "sk-test", session: session)

        var usage: AIUsage?
        for try await event in provider.stream(AIRequest(model: "gpt-5", messages: [.user("x")])) {
            if case let .completed(reported) = event { usage = reported }
        }

        #expect(usage == AIUsage(inputTokens: 30, outputTokens: 5))
    }

    // MARK: - 错误映射

    @Test(
        "HTTP 状态码分类",
        arguments: [
            (401, #"{"error":{"message":"invalid x-api-key"}}"#, AIError.unauthorized("invalid x-api-key")),
            (403, #"{"error":{"message":"no access"}}"#, AIError.forbidden("no access")),
            (404, #"{"error":{"message":"model not found"}}"#, AIError.notFound("model not found")),
            (429, #"{"error":{"message":"slow down"}}"#, AIError.rateLimited(retryAfter: nil)),
            (500, #"{"error":{"message":"boom"}}"#, AIError.serverError(status: 500, message: "boom")),
        ])
    func mapsStatusCodes(status: Int, body: String, expected: AIError) async throws {
        let session = StubURLProtocol.makeSession(json: body, statusCode: status)
        let provider = AnthropicProvider(apiKey: "bad", session: session)

        var caught: AIError?
        do {
            _ = try await provider.complete(AIRequest(model: "claude-opus-5", messages: [.user("x")]))
        } catch let error as AIError {
            caught = error
        }

        #expect(caught == expected)
    }

    @Test("上下文超长归到专门的分类")
    func detectsContextOverflow() async throws {
        // 两家都用 400 表示这个，只能靠报文关键词区分——归错类的话
        // 用户会看到「服务端错误，稍后重试」，然而重试一万次也没用
        let session = StubURLProtocol.makeSession(
            json: #"{"error":{"message":"prompt is too long: 250000 tokens > 200000 maximum"}}"#,
            statusCode: 400
        )
        let provider = AnthropicProvider(apiKey: "sk-test", session: session)

        var caught: AIError?
        do {
            _ = try await provider.complete(AIRequest(model: "claude-opus-5", messages: [.user("x")]))
        } catch let error as AIError {
            caught = error
        }

        let error = try #require(caught)
        guard case .contextTooLong = error else {
            Issue.record("应归为 contextTooLong，实际是 \(error)")
            return
        }
        #expect(error.isTransient == false)
    }

    @Test("错误信息挖不出来时不至于丢失原文")
    func fallsBackToRawBody() async throws {
        let session = StubURLProtocol.makeSession(json: "Bad Gateway", statusCode: 502)
        let provider = AnthropicProvider(apiKey: "sk-test", session: session)

        var caught: AIError?
        do {
            _ = try await provider.complete(AIRequest(model: "claude-opus-5", messages: [.user("x")]))
        } catch let error as AIError {
            caught = error
        }

        #expect(caught?.localizedMessage.contains("Bad Gateway") == true)
        #expect(caught?.isTransient == true)
    }
}
