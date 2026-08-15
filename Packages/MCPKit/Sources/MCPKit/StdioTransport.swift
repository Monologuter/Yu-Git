import Foundation

/// stdio 传输。
///
/// MCP 的 stdio 传输**按换行分隔消息**：一行一条 JSON，正文里不许有换行。
/// 所以这一层只做两件事——按行切进来的字节，写出去时补一个换行。
///
/// 单独成一层是因为它是唯一碰 IO 的部分。协议逻辑在 ``MCPServer`` 里，
/// 那部分能被完整测试；这里则只有几行，测不出什么，也没什么可错的。
public struct StdioTransport: Sendable {

    private let server: MCPServer

    public init(server: MCPServer) {
        self.server = server
    }

    /// 读到 EOF 为止。
    ///
    /// - Important: **绝不能往 stdout 写任何非协议内容。** 日志、进度、
    ///   调试信息一律走 stderr——stdout 是协议信道，混进一行别的东西，
    ///   客户端那边就是一条解析失败的消息，而且往往表现为「server 莫名其妙不响应了」。
    public func run() async {
        let input = FileHandle.standardInput
        let output = FileHandle.standardOutput

        var buffer = Data()
        while let chunk = try? input.read(upToCount: 4096), !chunk.isEmpty {
            buffer.append(chunk)

            // 一次可能读到多条，也可能读到半条，所以按换行逐条取
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)

                guard !line.isEmpty else { continue }
                if let response = await server.handle(Data(line)) {
                    try? output.write(contentsOf: response + Data([0x0A]))
                }
            }
        }

        // 对端关掉 stdin 之后，缓冲区里可能还剩最后一条没有换行结尾的消息
        if !buffer.isEmpty, let response = await server.handle(buffer) {
            try? output.write(contentsOf: response + Data([0x0A]))
        }
    }
}
