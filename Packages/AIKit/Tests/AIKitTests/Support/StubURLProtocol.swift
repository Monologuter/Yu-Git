import Foundation

/// 把一段预置的响应喂给 URLSession，用于在没有真 API Key 的情况下测 Provider。
///
/// 这里的 SSE 报文取自 Anthropic 与 OpenAI 的接口文档——和 GitKit 里
/// 「先采集真实 git 输出再写解析器」是同一条规矩：解析器要对着真实格式写，
/// 不能对着脑补的格式写。
final class StubURLProtocol: URLProtocol, @unchecked Sendable {

    struct Response {
        var statusCode: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
    }

    /// 下一个请求的响应。测试串行跑，用静态变量够用。
    nonisolated(unsafe) private static var stub: Response?
    /// 最近一次请求的报文，供断言检查请求组装是否正确。
    nonisolated(unsafe) private(set) static var lastRequest: URLRequest?
    nonisolated(unsafe) private(set) static var lastBody: Data?

    private static let lock = NSLock()

    static func setStub(_ response: Response) {
        lock.withLock {
            stub = response
            lastRequest = nil
            lastBody = nil
        }
    }

    static func setSSE(_ text: String, statusCode: Int = 200) {
        setStub(
            Response(
                statusCode: statusCode,
                headers: ["Content-Type": "text/event-stream"],
                body: Data(text.utf8)
            ))
    }

    static func setJSON(_ text: String, statusCode: Int = 200) {
        setStub(
            Response(
                statusCode: statusCode,
                headers: ["Content-Type": "application/json"],
                body: Data(text.utf8)
            ))
    }

    static func recordedRequest() -> (request: URLRequest?, body: Data?) {
        lock.withLock { (lastRequest, lastBody) }
    }

    /// 造一个只走桩的 session。
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // httpBody 在进到 URLProtocol 时可能已经变成 stream，两种都取一下
        let body = request.httpBody ?? request.httpBodyStream.map(Self.drain)

        let stub = Self.lock.withLock {
            Self.lastRequest = request
            Self.lastBody = body
            return Self.stub
        }

        guard let stub, let url = request.url else {
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
