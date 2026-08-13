import Foundation

/// 两家协议共用的 HTTP 收发层。
///
/// 只做三件事：发请求、把非 2xx 翻成 ``AIError``、把响应体切成 SSE 事件。
/// 「事件里装的是什么」由各自的 Provider 解释——那是两家协议唯一真正不同的地方。
struct HTTPTransport: Sendable {

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 发起流式请求，逐个交出 SSE 事件。
    func streamEvents(_ request: URLRequest) -> AsyncThrowingStream<SSEEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)

                    if let failure = Self.statusFailure(response) {
                        throw failure(await Self.collectBody(bytes))
                    }

                    var parser = SSEParser()
                    // URLSession.AsyncBytes 一次只给一个字节，攒到换行再交给解析器，
                    // 省掉每字节一次分配。批次边界怎么切都不影响解析结果。
                    var batch: [UInt8] = []
                    batch.reserveCapacity(4096)

                    for try await byte in bytes {
                        batch.append(byte)
                        guard byte == 0x0A else { continue }
                        for event in parser.consume(batch) { continuation.yield(event) }
                        batch.removeAll(keepingCapacity: true)
                    }

                    if !batch.isEmpty {
                        for event in parser.consume(batch) { continuation.yield(event) }
                    }
                    for event in parser.finish() { continuation.yield(event) }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIError.network(error.localizedDescription))
                }
            }

            // 用户改了主意就该立刻停下——流式生成可能要跑十几秒，
            // 不取消的话切走界面后还在烧 token。
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 发起普通请求，拿完整响应体。
    func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        if let failure = Self.statusFailure(response) {
            throw failure(String(decoding: data, as: UTF8.self))
        }
        return data
    }

    // MARK: - 内部

    /// 状态码不 OK 时返回一个「补上响应体就能得到错误」的函数。
    ///
    /// 分两步是因为流式场景下读响应体本身是异步的，而这里要同步判断状态码。
    private static func statusFailure(_ response: URLResponse) -> ((String) -> AIError)? {
        guard let http = response as? HTTPURLResponse else {
            return { _ in AIError.malformedResponse("不是 HTTP 响应") }
        }
        guard !(200..<300).contains(http.statusCode) else { return nil }

        let status = http.statusCode
        let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
        return { body in AIError.fromStatus(status, body: body, retryAfter: retryAfter) }
    }

    /// 读取错误响应体。读够看清错误信息就停，不必等完整。
    private static func collectBody(_ bytes: URLSession.AsyncBytes, limit: Int = 8192) async -> String {
        var buffer: [UInt8] = []
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= limit { break }
            }
        } catch {
            // 读错误体时又断了，就用已经读到的部分——总比什么都不告诉用户强
        }
        return String(decoding: buffer, as: UTF8.self)
    }
}
