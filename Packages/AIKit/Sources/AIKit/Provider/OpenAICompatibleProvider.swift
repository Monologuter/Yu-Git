import Foundation

/// OpenAI 兼容协议（`/v1/chat/completions`）。
///
/// 一个 Provider 覆盖一大票服务：OpenAI、DeepSeek、Kimi、通义、智谱、
/// 以及本地跑的 Ollama / LM Studio。它们都照抄了同一套接口，差别只在 base URL。
/// 这是驭Git 能做到「用户自己带 Key」的关键——不必为每家单独适配。
public struct OpenAICompatibleProvider: AIProvider {

    public static let defaultBaseURL: URL = .literal("https://api.openai.com/v1")

    public let displayName: String

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let transport: HTTPTransport

    /// - Parameter baseURL: 服务地址，需要含 `/v1`（各家惯例如此，例如
    ///   `https://api.deepseek.com/v1`、`http://localhost:11434/v1`）。
    public init(
        apiKey: String,
        baseURL: URL = OpenAICompatibleProvider.defaultBaseURL,
        displayName: String = "OpenAI 兼容",
        defaultModel: String = AIModelPresets.openAIDefault,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.displayName = displayName
        self.defaultModel = defaultModel
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
                var usage: AIUsage?

                do {
                    for try await event in transport.streamEvents(urlRequest) {
                        // 这套协议不用 event: 字段，全靠 data 里的哨兵值收尾
                        guard !event.data.isEmpty else { continue }
                        if event.data == "[DONE]" { break }

                        let chunk = try Self.decode(event.data)

                        if let error = chunk.error {
                            throw AIError.serverError(
                                status: 200,
                                message: error.message ?? "未知错误"
                            )
                        }

                        if let content = chunk.choices?.first?.delta?.content, !content.isEmpty {
                            continuation.yield(.textDelta(content))
                        }

                        // 只有开了 stream_options.include_usage 才会有；很多兼容服务
                        // 不认这个参数，所以不主动要，收到了才用。
                        if let reported = chunk.usage {
                            usage = AIUsage(
                                inputTokens: reported.promptTokens ?? 0,
                                outputTokens: reported.completionTokens ?? 0
                            )
                        }
                    }

                    continuation.yield(.completed(usage))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func validateCredentials() async throws {
        var request = try makeRequest(
            AIRequest(model: defaultModel, messages: [.user("hi")], maxTokens: 1),
            stream: false
        )
        request.timeoutInterval = 20
        _ = try await transport.send(request)
    }

    // MARK: - 组装请求

    private func makeRequest(_ request: AIRequest, stream: Bool) throws -> URLRequest {
        var urlRequest = URLRequest(url: baseURL.appending(path: "chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        // 这套协议里 system 是 messages 的第一条，不是顶层字段
        var messages: [[String: String]] = []
        if let system = request.system {
            messages.append(["role": "system", "content": system])
        }
        messages += request.messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        var body: [String: Any] = [
            "model": request.model,
            "messages": messages,
            "max_tokens": request.maxTokens,
        ]
        if stream { body["stream"] = true }

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

    private struct StreamChunk: Decodable {
        let choices: [Choice]?
        let usage: Usage?
        let error: ErrorInfo?

        struct Choice: Decodable {
            let delta: Delta?

            struct Delta: Decodable {
                let content: String?
            }
        }

        struct Usage: Decodable {
            let promptTokens: Int?
            let completionTokens: Int?
        }

        struct ErrorInfo: Decodable {
            let message: String?
        }
    }
}
