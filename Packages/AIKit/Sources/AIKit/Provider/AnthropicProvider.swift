import Foundation

/// Anthropic 原生 Messages API。
///
/// 与 OpenAI 兼容协议的三处关键差异，也是必须单独写一个 Provider 的原因：
/// - 认证走 `x-api-key` 而不是 `Authorization: Bearer`
/// - 必须带 `anthropic-version` 头
/// - system 提示在顶层字段，不在 messages 数组里
/// - SSE 用 `event:` 区分事件类型，正文藏在 `content_block_delta` 里
public struct AnthropicProvider: AIProvider {

    /// Anthropic 要求的 API 版本。这是日期化的契约版本号，不是模型版本，
    /// 不随模型更新而变——写死是对的。
    static let apiVersion = "2023-06-01"

    public static let defaultBaseURL: URL = .literal("https://api.anthropic.com")

    public let displayName = "Anthropic"

    private let apiKey: String
    private let baseURL: URL
    private let transport: HTTPTransport

    public init(apiKey: String, baseURL: URL = AnthropicProvider.defaultBaseURL, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.transport = HTTPTransport(session: session)
    }

    // MARK: - AIProvider

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, any Error> {
        let urlRequest: URLRequest
        do {
            urlRequest = try makeRequest(request, stream: true)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var inputTokens = 0
                var outputTokens = 0

                do {
                    for try await event in transport.streamEvents(urlRequest) {
                        // ping 是心跳，没有 data 负载
                        guard event.name != "ping", !event.data.isEmpty else { continue }

                        let chunk = try Self.decode(event.data)

                        if let error = chunk.error {
                            throw AIError.serverError(
                                status: 200,
                                message: error.message ?? error.type ?? "未知错误"
                            )
                        }

                        switch chunk.type {
                        case "message_start":
                            inputTokens = chunk.message?.usage?.inputTokens ?? 0

                        case "content_block_delta":
                            // 只取正文。thinking_delta / input_json_delta 都不是要展示的内容——
                            // 混进来会把模型的思考过程直接写进提交信息。
                            if chunk.delta?.type == "text_delta", let text = chunk.delta?.text {
                                continuation.yield(.textDelta(text))
                            }

                        case "message_delta":
                            outputTokens = chunk.usage?.outputTokens ?? outputTokens
                            // 安全分类器可能拒绝请求，此时是 200 而不是错误状态码。
                            // 不检查的话用户只会看到空白输出，不知道发生了什么。
                            if chunk.delta?.stopReason == "refusal" {
                                throw AIError.forbidden("模型拒绝了这次请求")
                            }

                        default:
                            break
                        }
                    }

                    continuation.yield(
                        .completed(AIUsage(inputTokens: inputTokens, outputTokens: outputTokens)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func validateCredentials() async throws {
        // max_tokens = 1 的最小请求：够验证 Key 和模型可达，又几乎不花钱
        var request = try makeRequest(
            AIRequest(model: AIModelPresets.anthropicDefault, messages: [.user("hi")], maxTokens: 1),
            stream: false
        )
        request.timeoutInterval = 20
        _ = try await transport.send(request)
    }

    // MARK: - 组装请求

    private func makeRequest(_ request: AIRequest, stream: Bool) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: "/v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if let system = request.system { body["system"] = system }
        if stream { body["stream"] = true }

        // 刻意不发 thinking 和 effort：驭Git 让用户自己填模型名，而这两个参数在不同
        // 模型上的合法取值不一样（老模型收 budget_tokens，新模型收 adaptive，
        // 有的直接 400）。全都不发，各模型用自己的默认值，才不会因为选了某个模型就报错。
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    // MARK: - 解析响应

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static func decode(_ json: String) throws -> StreamChunk {
        guard let data = json.data(using: .utf8) else {
            throw AIError.malformedResponse("事件不是合法 UTF-8")
        }
        do {
            return try decoder.decode(StreamChunk.self, from: data)
        } catch {
            throw AIError.malformedResponse(String(json.prefix(200)))
        }
    }

    /// SSE 各类事件的并集。字段几乎全是可选的——同一个流里不同事件带的字段不一样，
    /// 与其为六种事件写六个类型再分发，不如用一个宽松结构按 `type` 取用。
    private struct StreamChunk: Decodable {
        let type: String
        let delta: Delta?
        let message: MessageInfo?
        let usage: Usage?
        let error: ErrorInfo?

        struct Delta: Decodable {
            let type: String?
            let text: String?
            let stopReason: String?
        }

        struct MessageInfo: Decodable {
            let usage: Usage?
        }

        struct Usage: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
        }

        struct ErrorInfo: Decodable {
            let type: String?
            let message: String?
        }
    }
}
