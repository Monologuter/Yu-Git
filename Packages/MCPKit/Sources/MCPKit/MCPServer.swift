import Foundation

/// MCP 协议里的一个工具。
public struct MCPTool: Sendable {

    public let name: String
    /// 给模型看的说明。**这段话决定模型会不会在对的时候用它**，
    /// 所以要写「什么时候该用」，而不只是「它做什么」。
    public let description: String
    /// 参数的 JSON Schema。
    public let inputSchema: JSONValue
    /// 真正干活的闭包。
    public let handler: @Sendable ([String: JSONValue]) async throws -> String

    public init(
        name: String,
        description: String,
        inputSchema: JSONValue,
        handler: @escaping @Sendable ([String: JSONValue]) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.handler = handler
    }
}

/// MCP server 的协议处理。
///
/// **方向反转**是这个东西存在的全部意义：此前是驭Git 调 AI，
/// MCP 让 Claude Code 反过来调驭Git。GUI 因此成为 agent 的操作台，
/// 而不是 agent 的替代品——「AI 帮你写代码，驭Git 帮你驾驭它」
/// 到这里才真正兑现。
///
/// 这个类型只管协议，不碰 IO：喂给它一条请求，它返回该发回去的字节。
/// 传输层（stdio）另在 `StdioTransport` 里。分开是因为协议这一层的坑
/// 全部可以用纯函数测出来，而混进 IO 之后就只能靠手工跑。
public actor MCPServer {

    public static let protocolVersion = "2024-11-05"

    private let serverName: String
    private let serverVersion: String
    private var tools: [String: MCPTool] = [:]
    private var toolOrder: [String] = []

    /// 客户端有没有握过手。
    ///
    /// 规范要求 `initialize` 之后才谈别的。不拦的话，一个还没协商完协议版本的
    /// 客户端就能调用工具——而那些工具是会写用户仓库的。
    private var isInitialized = false

    public init(name: String, version: String) {
        self.serverName = name
        self.serverVersion = version
    }

    public func register(_ tool: MCPTool) {
        if tools[tool.name] == nil {
            toolOrder.append(tool.name)
        }
        tools[tool.name] = tool
    }

    /// 处理一条消息，返回该写回去的字节。
    ///
    /// - Returns: 通知（没有 id）返回 nil——规范规定通知**一律不回响应**。
    public func handle(_ data: Data) async -> Data? {
        let request: RPCRequest
        do {
            request = try JSONRPC.decode(data)
        } catch let error as RPCError {
            // 解析失败时拿不到 id，按规范回 id: null
            return try? JSONRPC.encodeError(id: nil, error: error)
        } catch {
            return try? JSONRPC.encodeError(
                id: nil, error: RPCError(code: .parseError, message: "\(error)"))
        }

        // 通知不回。`notifications/initialized` 是最常见的一条，
        // 回了它的话客户端会收到一条对不上任何请求的响应。
        guard let id = request.id else {
            if request.method == "notifications/initialized" {
                isInitialized = true
            }
            return nil
        }

        do {
            let result = try await respond(to: request)
            return try JSONRPC.encodeResult(id: id, result: result)
        } catch let error as RPCError {
            return try? JSONRPC.encodeError(id: id, error: error)
        } catch {
            return try? JSONRPC.encodeError(
                id: id, error: RPCError(code: .internalError, message: "\(error)"))
        }
    }

    private func respond(to request: RPCRequest) async throws -> JSONValue {
        switch request.method {
        case "initialize":
            isInitialized = true
            return .object([
                "protocolVersion": .string(Self.protocolVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string(serverName),
                    "version": .string(serverVersion),
                ]),
            ])

        case "ping":
            // 健康检查，握手之前也该答——客户端拿它确认进程还活着
            return .object([:])

        case "tools/list":
            try requireInitialized()
            return .object([
                "tools": .array(
                    toolOrder.compactMap { tools[$0] }.map { tool in
                        .object([
                            "name": .string(tool.name),
                            "description": .string(tool.description),
                            "inputSchema": tool.inputSchema,
                        ])
                    })
            ])

        case "tools/call":
            try requireInitialized()
            guard let name = request.params["name"]?.stringValue else {
                throw RPCError(code: .invalidParams, message: "缺少工具名")
            }
            guard let tool = tools[name] else {
                throw RPCError(code: .methodNotFound, message: "没有名叫 \(name) 的工具")
            }

            let arguments = request.params["arguments"]?.objectValue ?? [:]
            do {
                let text = try await tool.handler(arguments)
                return .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])])
                ])
            } catch {
                // 工具自己失败**不是协议错误**：按规范应当返回一个标了 isError
                // 的正常结果，让模型看到失败原因并自己决定下一步。
                // 回 JSON-RPC error 的话，多数客户端会把它当成 server 出故障。
                return .object([
                    "content": .array([
                        .object(["type": .string("text"), "text": .string("\(error)")])
                    ]),
                    "isError": .bool(true),
                ])
            }

        default:
            throw RPCError(code: .methodNotFound, message: "不支持的方法：\(request.method)")
        }
    }

    private func requireInitialized() throws {
        guard isInitialized else {
            throw RPCError(code: .invalidRequest, message: "请先调用 initialize")
        }
    }
}
