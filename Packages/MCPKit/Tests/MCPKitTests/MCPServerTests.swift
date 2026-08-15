import Foundation
import Testing

@testable import MCPKit

@Suite("MCP 协议")
struct MCPServerTests {

    /// 造一个装了假工具的 server，握手已完成。
    private func readyServer(
        toolName: String = "echo",
        handler: @escaping @Sendable ([String: JSONValue]) async throws -> String = { _ in "好了" }
    ) async -> MCPServer {
        let server = MCPServer(name: "测试", version: "1.0")
        await server.register(
            MCPTool(
                name: toolName,
                description: "回显",
                inputSchema: .object(["type": .string("object")]),
                handler: handler
            ))
        _ = await server.handle(request(id: 1, method: "initialize"))
        return server
    }

    /// 造一条请求。
    ///
    /// 序列化失败时返回空 Data 而不是崩：这里拼的都是字面量，失败不可能发生，
    /// 而为一个不可能发生的分支写 `try!` 会被格式检查拦下。
    private func request(id: Any?, method: String, params: [String: Any] = [:]) -> Data {
        var object: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let id { object["id"] = id }
        if !params.isEmpty { object["params"] = params }
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private func decode(_ data: Data?) -> [String: Any]? {
        guard let data else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - 握手

    @Test("initialize 回协议版本与服务器信息")
    func handshakes() async throws {
        let server = MCPServer(name: "yugit", version: "1.0.0")

        let response = decode(await server.handle(request(id: 1, method: "initialize")))
        let result = try #require(response?["result"] as? [String: Any])

        #expect(result["protocolVersion"] as? String == MCPServer.protocolVersion)
        let info = try #require(result["serverInfo"] as? [String: Any])
        #expect(info["name"] as? String == "yugit")
        // 声明了 tools 能力，客户端才会来问 tools/list
        #expect(result["capabilities"] as? [String: Any] != nil)
    }

    /// 规范要求先 `initialize`。不拦的话，一个还没协商完协议版本的客户端
    /// 就能调用工具——而这些工具是会写用户仓库的。
    @Test("没握手就调工具会被拒绝")
    func refusesBeforeInitialize() async throws {
        let server = MCPServer(name: "测试", version: "1.0")

        let response = decode(await server.handle(request(id: 1, method: "tools/list")))

        #expect(response?["result"] == nil)
        let error = try #require(response?["error"] as? [String: Any])
        #expect(error["code"] as? Int == RPCErrorCode.invalidRequest.rawValue)
    }

    /// **通知一律不回响应。** 回了的话客户端会收到一条它从未请求过的消息，
    /// 多数实现直接报协议错误。
    @Test("通知没有响应")
    func neverRespondsToNotifications() async {
        let server = MCPServer(name: "测试", version: "1.0")

        let response = await server.handle(
            request(id: nil, method: "notifications/initialized"))

        #expect(response == nil)
    }

    @Test("initialized 通知本身也算完成了握手")
    func notificationCompletesHandshake() async throws {
        let server = MCPServer(name: "测试", version: "1.0")
        _ = await server.handle(request(id: nil, method: "notifications/initialized"))

        let response = decode(await server.handle(request(id: 1, method: "tools/list")))
        #expect(response?["result"] != nil)
    }

    @Test("ping 在握手之前也答，客户端拿它确认进程还活着")
    func answersPingBeforeHandshake() async throws {
        let server = MCPServer(name: "测试", version: "1.0")

        let response = decode(await server.handle(request(id: 9, method: "ping")))
        #expect(response?["result"] != nil)
    }

    // MARK: - id 的形态

    /// **id 可能是数字也可能是字符串，响应必须原样回同一种。**
    /// 统一转成字符串的话，客户端拿数字 id 发的请求会收到字符串 id 的响应，
    /// 严格的客户端会认为那是一条对不上号的消息。
    @Test("数字 id 回数字，字符串 id 回字符串")
    func preservesTheIdentifierKind() async throws {
        let server = await readyServer()

        let numeric = decode(await server.handle(request(id: 42, method: "tools/list")))
        #expect(numeric?["id"] as? Int == 42)

        let textual = decode(await server.handle(request(id: "abc", method: "tools/list")))
        #expect(textual?["id"] as? String == "abc")
    }

    /// 解析失败时拿不到 id，按规范要回 `id: null`，不能省掉这个字段。
    @Test("解析不了的输入回一条 id 为 null 的错误")
    func reportsParseErrors() async throws {
        let server = MCPServer(name: "测试", version: "1.0")

        let response = decode(await server.handle(Data("这不是 JSON".utf8)))

        let error = try #require(response?["error"] as? [String: Any])
        #expect(error["code"] as? Int == RPCErrorCode.parseError.rawValue)
        #expect(response?["id"] is NSNull)
    }

    @Test("是 JSON 但缺 method 时报的是 invalidRequest，不是 parseError")
    func distinguishesInvalidRequests() async throws {
        let server = MCPServer(name: "测试", version: "1.0")
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1])

        let response = decode(await server.handle(data))

        let error = try #require(response?["error"] as? [String: Any])
        #expect(error["code"] as? Int == RPCErrorCode.invalidRequest.rawValue)
    }

    // MARK: - 工具

    @Test("tools/list 列出注册过的工具及其 schema")
    func listsTools() async throws {
        let server = await readyServer(toolName: "yugit_snapshot")

        let response = decode(await server.handle(request(id: 1, method: "tools/list")))
        let result = try #require(response?["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])

        #expect(tools.count == 1)
        #expect(tools[0]["name"] as? String == "yugit_snapshot")
        #expect(tools[0]["inputSchema"] != nil)
        // 说明不能为空：那段话决定模型会不会在对的时候用它
        #expect(!((tools[0]["description"] as? String) ?? "").isEmpty)
    }

    @Test("调用工具，参数传得进去，结果按 content 数组回")
    func callsATool() async throws {
        let server = await readyServer { arguments in
            "收到：\(arguments["label"]?.stringValue ?? "")"
        }

        let response = decode(
            await server.handle(
                request(
                    id: 1, method: "tools/call",
                    params: ["name": "echo", "arguments": ["label": "测试标签"]])))

        let result = try #require(response?["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(content[0]["type"] as? String == "text")
        #expect(content[0]["text"] as? String == "收到：测试标签")
    }

    /// **工具自己失败不是协议错误。** 按规范该返回一个标了 isError 的正常结果，
    /// 让模型看到失败原因并自己决定下一步。回 JSON-RPC error 的话，
    /// 多数客户端会把它当成 server 出故障。
    @Test("工具抛错时回 isError 结果，不是协议错误")
    func reportsToolFailuresAsResults() async throws {
        let server = await readyServer { _ in
            throw ToolError.missingArgument("label")
        }

        let response = decode(
            await server.handle(
                request(id: 1, method: "tools/call", params: ["name": "echo"])))

        #expect(response?["error"] == nil)
        let result = try #require(response?["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
        let content = try #require(result["content"] as? [[String: Any]])
        #expect(((content[0]["text"] as? String) ?? "").contains("label"))
    }

    @Test("调不存在的工具是 methodNotFound")
    func rejectsUnknownTools() async throws {
        let server = await readyServer()

        let response = decode(
            await server.handle(
                request(id: 1, method: "tools/call", params: ["name": "没有这个"])))

        let error = try #require(response?["error"] as? [String: Any])
        #expect(error["code"] as? Int == RPCErrorCode.methodNotFound.rawValue)
    }

    @Test("不认识的方法不会让连接死掉，只回一条错误")
    func survivesUnknownMethods() async throws {
        let server = await readyServer()

        let response = decode(await server.handle(request(id: 1, method: "resources/list")))
        #expect(response?["error"] != nil)

        // 之后仍然能正常干活
        let next = decode(await server.handle(request(id: 2, method: "tools/list")))
        #expect(next?["result"] != nil)
    }

    // MARK: - 编码

    /// **响应必须是一行。** MCP 的 stdio 传输按换行分隔消息，
    /// 正文里出现换行就会把一条切成两条，之后整条连接的解析全部错位。
    @Test("响应里不含换行，哪怕工具返回的文本有换行")
    func encodesOnASingleLine() async throws {
        let server = await readyServer { _ in "第一行\n第二行\n第三行" }

        let data = try #require(
            await server.handle(
                request(id: 1, method: "tools/call", params: ["name": "echo"])))

        #expect(!data.contains(0x0A))
        // 但内容本身要完整保留，只是被转义了
        let result = decode(data)?["result"] as? [String: Any]
        let content = try #require(result?["content"] as? [[String: Any]])
        #expect(content[0]["text"] as? String == "第一行\n第二行\n第三行")
    }

    @Test("中文与斜杠都原样带回去")
    func keepsTextIntact() async throws {
        let server = await readyServer { _ in "路径 /Users/x/项目 里的「引号」" }

        let data = try #require(
            await server.handle(
                request(id: 1, method: "tools/call", params: ["name": "echo"])))
        let result = decode(data)?["result"] as? [String: Any]
        let content = try #require(result?["content"] as? [[String: Any]])

        #expect(content[0]["text"] as? String == "路径 /Users/x/项目 里的「引号」")
    }

    @Test("重复注册同名工具是覆盖，列表里不出现两次")
    func replacesDuplicateTools() async throws {
        let server = MCPServer(name: "测试", version: "1.0")
        for index in 0..<2 {
            await server.register(
                MCPTool(
                    name: "same", description: "第 \(index) 版",
                    inputSchema: .object([:]), handler: { _ in "" }))
        }
        _ = await server.handle(request(id: 1, method: "initialize"))

        let response = decode(await server.handle(request(id: 2, method: "tools/list")))
        let tools = try #require((response?["result"] as? [String: Any])?["tools"] as? [[String: Any]])

        #expect(tools.count == 1)
        #expect(tools[0]["description"] as? String == "第 1 版")
    }
}

@Suite("JSON-RPC 编解码")
struct JSONRPCTests {

    @Test("认得出通知")
    func detectsNotifications() throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        let request = try JSONRPC.decode(data)

        #expect(request.isNotification)
        #expect(request.id == nil)
    }

    /// JSON 里的 `true` 也会解成 NSNumber。当成数字 1 处理的话，
    /// 响应的 id 会变成 1，和客户端发的对不上。
    @Test("布尔的 id 不当作数字")
    func rejectsBooleanIdentifiers() throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["jsonrpc": "2.0", "id": true, "method": "ping"])
        let request = try JSONRPC.decode(data)

        #expect(request.id == nil)
    }

    @Test("嵌套参数解得出来")
    func decodesNestedParameters() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "jsonrpc": "2.0", "id": 1, "method": "tools/call",
                "params": [
                    "name": "x",
                    "arguments": ["limit": 20, "flag": true, "list": ["a", "b"]],
                ],
            ])
        let request = try JSONRPC.decode(data)

        let arguments = try #require(request.params["arguments"]?.objectValue)
        #expect(arguments["limit"]?.intValue == 20)
        #expect(arguments["flag"]?.boolValue == true)
        #expect(arguments["list"]?.arrayValue?.count == 2)
    }

    /// 参数是外部输入，客户端传什么都不该让 server 崩。
    @Test("取错类型返回 nil 而不是崩")
    func returnsNilForWrongTypes() throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "jsonrpc": "2.0", "id": 1, "method": "x",
                "params": ["count": "不是数字"],
            ])
        let request = try JSONRPC.decode(data)

        #expect(request.params["count"]?.intValue == nil)
        #expect(request.params["count"]?.stringValue == "不是数字")
        #expect(request.params["缺席的"] == nil)
    }

    @Test("method 为空串按 invalidRequest 处理")
    func rejectsEmptyMethods() throws {
        let data = try JSONSerialization.data(
            withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": ""])

        #expect(throws: RPCError.self) {
            _ = try JSONRPC.decode(data)
        }
    }
}
