import Foundation

/// 把一段预置的响应喂给 URLSession，用于在没有真 API Key 的情况下测 Provider。
///
/// 这里的 SSE 报文取自 Anthropic 与 OpenAI 的接口文档——和 GitKit 里
/// 「先采集真实 git 输出再写解析器」是同一条规矩：解析器要对着真实格式写，
/// 不能对着脑补的格式写。
///
/// **状态按 session 隔离**，不是全局一份。`.serialized` 只在单个 suite 内串行，
/// 不同 suite 之间仍然并行——共用一份静态桩会让两个 suite 互相覆盖对方的响应。
/// 每个 session 带一个 token 走 `httpAdditionalHeaders`，各查各的。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    struct Stub {
        var statusCode: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
    }

    private struct Record {
        var request: URLRequest?
        var body: Data?
    }

    static let tokenHeader = "X-Yugit-Stub-Token"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]
    nonisolated(unsafe) private static var records: [String: Record] = [:]

    // MARK: - 造 session

    /// 造一个只走桩的 session，桩内容与它一一绑定。
    static func makeSession(stub: Stub) -> URLSession {
        let token = UUID().uuidString
        lock.withLock { stubs[token] = stub }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [tokenHeader: token]
        return URLSession(configuration: configuration)
    }

    static func makeSession(sse: String, statusCode: Int = 200) -> URLSession {
        makeSession(
            stub: Stub(
                statusCode: statusCode,
                headers: ["Content-Type": "text/event-stream"],
                body: Data(sse.utf8)
            ))
    }

    static func makeSession(json: String, statusCode: Int = 200) -> URLSession {
        makeSession(
            stub: Stub(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                body: Data(json.utf8)
            ))
    }

    /// 取这个 session 上最近一次请求，供断言检查请求组装是否正确。
    static func recordedRequest(for session: URLSession) -> (request: URLRequest?, body: Data?) {
        guard let token = session.configuration.httpAdditionalHeaders?[tokenHeader] as? String
        else { return (nil, nil) }

        let record = lock.withLock { records[token] }
        return (record?.request, record?.body)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // httpBody 进到 URLProtocol 时可能已经变成 stream，两种都取一下
        let body = request.httpBody ?? request.httpBodyStream.map(Self.drain)

        guard
            let token = request.value(forHTTPHeaderField: Self.tokenHeader),
            let url = request.url
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let stub = Self.lock.withLock {
            Self.records[token] = Record(request: request, body: body)
            return Self.stubs[token]
        }

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
            )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotParseResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
