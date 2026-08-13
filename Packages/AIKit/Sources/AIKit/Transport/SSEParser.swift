import Foundation

/// 一个 Server-Sent Events 事件。
public struct SSEEvent: Sendable, Equatable {
    /// `event:` 字段。Anthropic 会填（`content_block_delta` 等），OpenAI 兼容协议不填。
    public let name: String?
    /// 所有 `data:` 行按换行拼起来的内容。
    public let data: String

    public init(name: String?, data: String) {
        self.name = name
        self.data = data
    }
}

/// 增量式 SSE 解析器。
///
/// 两处必须按字节而不是按 `String` 处理：
///
/// 1. **分块边界**。URLSession 交下来的 `Data` 块与事件边界毫无关系，一个 JSON
///    可能被劈成三块，甚至劈在一个 UTF-8 多字节汉字中间——先转 String 会得到乱码。
///    所以先在字节层面切出完整的行，再把行转成字符串。
/// 2. **行结束符**。SSE 规范允许 `\n`、`\r\n`、`\r` 三种，而 Swift 把 `"\r\n"` 当作
///    **一个** Character，`String.split(separator: "\n")` 根本切不开 CRLF 流。
///
/// 解析器持有跨块的状态，所以是 `mutating` 的值类型，由单个 Task 顺序驱动。
public struct SSEParser: Sendable {

    private var buffer: [UInt8] = []
    private var pendingName: String?
    private var pendingData: [String] = []

    public init() {}

    /// 吃进一块网络数据，吐出其中已完整的事件。
    ///
    /// 接受任意字节序列而不只是 `Data`：`URLSession.AsyncBytes` 逐字节交付，
    /// 攒成 `[UInt8]` 批量喂进来能省掉每字节一次 `Data` 分配。
    public mutating func consume(_ chunk: some Sequence<UInt8>) -> [SSEEvent] {
        buffer.append(contentsOf: chunk)
        return drainCompleteLines()
    }

    /// 流结束时调用，交出最后一个没有以空行收尾的事件。
    ///
    /// 规范说 EOF 时应丢弃未完成的事件，这里选择交出来：真被截断的话，
    /// 残缺的 JSON 会在解码时报错，用户看到「响应解析失败」；而静默丢弃只会
    /// 让人拿到半句话却毫不知情。宁可报错也不要静默截断。
    public mutating func finish() -> [SSEEvent] {
        var events = drainCompleteLines()

        // 缓冲里可能还剩最后一行没有行结束符
        if !buffer.isEmpty {
            let line = String(decoding: buffer, as: UTF8.self)
            buffer.removeAll()
            handle(line: line)
        }

        if let event = flushPending() { events.append(event) }
        return events
    }

    // MARK: - 内部

    private mutating func drainCompleteLines() -> [SSEEvent] {
        var events: [SSEEvent] = []
        var lineStart = 0
        var index = 0

        while index < buffer.count {
            let byte = buffer[index]
            guard byte == 0x0A || byte == 0x0D else {
                index += 1
                continue
            }

            var nextStart = index + 1
            if byte == 0x0D {
                // 可能是 CRLF，也可能是单独的 CR。缓冲刚好在 CR 后断掉时无法判断，
                // 先留着等下一块数据——否则会把一个 CRLF 误当成两个空行，
                // 凭空多切出一个事件。
                if nextStart == buffer.count { break }
                if buffer[nextStart] == 0x0A { nextStart += 1 }
            }

            let line = String(decoding: buffer[lineStart..<index], as: UTF8.self)
            if line.isEmpty {
                if let event = flushPending() { events.append(event) }
            } else {
                handle(line: line)
            }

            lineStart = nextStart
            index = nextStart
        }

        if lineStart > 0 { buffer.removeFirst(lineStart) }
        return events
    }

    private mutating func handle(line: String) {
        // 以冒号开头的是注释。有些服务端拿它当心跳，必须忽略而不是当成数据。
        guard !line.hasPrefix(":") else { return }

        let field: String
        var value: String

        if let colon = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colon])
            value = String(line[line.index(after: colon)...])
            // 规范：只去掉一个前导空格
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event": pendingName = value
        case "data": pendingData.append(value)
        default: break  // id / retry 用不上
        }
    }

    private mutating func flushPending() -> SSEEvent? {
        guard !pendingData.isEmpty || pendingName != nil else { return nil }
        let event = SSEEvent(name: pendingName, data: pendingData.joined(separator: "\n"))
        pendingName = nil
        pendingData.removeAll()
        return event
    }
}
