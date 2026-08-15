import Foundation

// MCP 走的是 JSON-RPC 2.0。这个文件只管协议本身的编解码，不认识任何驭Git 的概念——
// 分开是为了让协议部分能被完整测试：它是纯函数，输入一段字节、输出一段字节，
// 而 MCP 最容易出错的地方恰恰在这一层（通知不能回响应、错误码要对得上、
// 未知方法不能让整个连接死掉）。

/// 一条 JSON-RPC 请求。
public struct RPCRequest: Sendable, Equatable {

    /// 请求标识。
    ///
    /// **可能是数字也可能是字符串**，规范两种都允许，而且响应里必须原样回同一种。
    /// 统一转成字符串再回去的话，客户端拿数字 id 发的请求会收到字符串 id 的响应，
    /// 严格的客户端会认为那是一条对不上号的消息。
    public enum Identifier: Sendable, Equatable {
        case number(Int)
        case string(String)
    }

    /// 没有 id 的请求是**通知**，规范规定**一律不许回响应**。
    /// 回了的话，客户端收到一条它从未请求过的响应，多数实现会直接报协议错误。
    public let id: Identifier?
    public let method: String
    public let params: [String: JSONValue]

    public var isNotification: Bool { id == nil }

    public init(id: Identifier?, method: String, params: [String: JSONValue] = [:]) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC 的标准错误码。
public enum RPCErrorCode: Int, Sendable {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
}

public struct RPCError: Error, Sendable, Equatable {
    public let code: Int
    public let message: String

    public init(code: RPCErrorCode, message: String) {
        self.code = code.rawValue
        self.message = message
    }

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}

/// 极简的 JSON 值。
///
/// 不用 `Any`：MCP 的参数结构是嵌套的，而 `Any` 一旦进来，每一处取值都要 `as?`，
/// 类型错误要到运行时才发现。这个枚举让编解码和取值都能被编译器检查。
public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    // 取值助手。取错类型返回 nil 而不是崩——参数是外部输入，
    // 客户端传什么都不该让 server 挂掉。
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        if case .number(let value) = self { return Int(value) }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

/// JSON-RPC 消息的编解码。
public enum JSONRPC {

    /// 解析一条消息。
    ///
    /// - Throws: 解析不了时抛 `parseError`，缺字段时抛 `invalidRequest`——
    ///   两者的错误码不同，客户端据此区分「你发的不是 JSON」和「是 JSON 但不合规」。
    public static func decode(_ data: Data) throws -> RPCRequest {
        guard let raw = try? JSONSerialization.jsonObject(with: data),
            let object = raw as? [String: Any]
        else {
            throw RPCError(code: .parseError, message: "不是合法的 JSON")
        }

        guard let method = object["method"] as? String, !method.isEmpty else {
            throw RPCError(code: .invalidRequest, message: "缺少 method")
        }

        var identifier: RPCRequest.Identifier?
        if let value = object["id"], !(value is NSNull) {
            // JSON 里的 true/false 也会解成 NSNumber，先排掉——
            // `id: true` 不是合法标识，当成数字 1 处理会让响应对不上号
            if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                identifier = .number(number.intValue)
            } else if let text = value as? String {
                identifier = .string(text)
            }
        }

        let params = (object["params"] as? [String: Any]).map(convert) ?? [:]
        return RPCRequest(id: identifier, method: method, params: params)
    }

    /// 编码一条成功响应。
    public static func encodeResult(id: RPCRequest.Identifier, result: JSONValue) throws -> Data {
        var object: [String: Any] = ["jsonrpc": "2.0", "result": unwrap(result)]
        object["id"] = unwrapIdentifier(id)
        return try serialize(object)
    }

    /// 编码一条错误响应。
    public static func encodeError(id: RPCRequest.Identifier?, error: RPCError) throws -> Data {
        var object: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": error.code, "message": error.message],
        ]
        // id 拿不到时按规范填 null，不能省掉这个字段
        object["id"] = id.map(unwrapIdentifier) ?? NSNull()
        return try serialize(object)
    }

    /// 序列化成一行。
    ///
    /// **必须是一行。** MCP 的 stdio 传输按换行分隔消息，正文里出现换行就会
    /// 把一条消息切成两条，之后整条连接的解析全部错位。
    /// `.withoutEscapingSlashes` 只是让路径读起来正常，不影响正确性。
    private static func serialize(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object, options: [.withoutEscapingSlashes])
    }

    private static func unwrapIdentifier(_ id: RPCRequest.Identifier) -> Any {
        switch id {
        case .number(let value): value
        case .string(let value): value
        }
    }

    static func convert(_ object: [String: Any]) -> [String: JSONValue] {
        object.mapValues(convert)
    }

    static func convert(_ value: Any) -> JSONValue {
        switch value {
        case is NSNull: .null
        case let number as NSNumber:
            CFGetTypeID(number) == CFBooleanGetTypeID()
                ? .bool(number.boolValue) : .number(number.doubleValue)
        case let text as String: .string(text)
        case let array as [Any]: .array(array.map(convert))
        case let object as [String: Any]: .object(convert(object))
        default: .null
        }
    }

    static func unwrap(_ value: JSONValue) -> Any {
        switch value {
        case .null: NSNull()
        case .bool(let inner): inner
        case .number(let inner): inner
        case .string(let inner): inner
        case .array(let inner): inner.map(unwrap)
        case .object(let inner): inner.mapValues(unwrap)
        }
    }
}
