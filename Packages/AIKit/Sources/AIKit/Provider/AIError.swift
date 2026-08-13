import Foundation

/// AI 调用失败的分类。
///
/// 和 ``RemoteError`` 同一个思路：把服务端五花八门的报错归到用户能看懂的几类，
/// 每类给一句「那我该怎么办」。BYOK 场景下这尤其重要——用户配的是自己的 Key 和
/// 自己的服务商，出问题时他确实有能力自己修，前提是知道要修哪。
public enum AIError: Error, Sendable, Equatable {

    /// Key 无效或没配。
    case unauthorized(String)
    /// 没有权限用这个模型，或者账号欠费。
    case forbidden(String)
    /// 模型名不对，或者服务地址填错。
    case notFound(String)
    /// 触发限流。
    case rateLimited(retryAfter: TimeInterval?)
    /// 请求过大，通常是 diff 太长超了上下文。
    case contextTooLong(String)
    /// 服务端自己出错。
    case serverError(status: Int, message: String)
    /// 网络层失败。
    case network(String)
    /// 响应格式不认识。
    case malformedResponse(String)
    /// 没配置任何 provider。
    case notConfigured

    /// 给用户看的一句话。
    public var localizedMessage: String {
        switch self {
        case let .unauthorized(detail): "API Key 无效或已失效：\(detail)"
        case let .forbidden(detail): "没有权限访问该模型：\(detail)"
        case let .notFound(detail): "找不到模型或接口地址：\(detail)"
        case .rateLimited: "请求太频繁，被服务商限流了"
        case let .contextTooLong(detail): "内容超出模型上下文长度：\(detail)"
        case let .serverError(status, message): "服务端错误（\(status)）：\(message)"
        case let .network(detail): "网络连接失败：\(detail)"
        case let .malformedResponse(detail): "响应解析失败：\(detail)"
        case .notConfigured: "还没有配置 AI 服务"
        }
    }

    /// 建议的下一步。
    public var suggestion: String {
        switch self {
        case .unauthorized:
            "到「设置 → AI」检查 API Key 是否填对、是否已过期"
        case .forbidden:
            "确认账号已开通该模型的访问权限，以及余额是否充足"
        case .notFound:
            "检查模型名称拼写，以及接口地址是否正确（OpenAI 兼容服务通常以 /v1 结尾）"
        case let .rateLimited(retryAfter):
            if let seconds = retryAfter {
                "等待约 \(Int(seconds)) 秒后重试，或在设置里换一个额度更充裕的模型"
            } else {
                "稍后重试，或在设置里换一个额度更充裕的模型"
            }
        case .contextTooLong:
            "改动太大了。可以只选一部分文件让 AI 处理，或换一个上下文更长的模型"
        case .serverError:
            "这是服务商侧的问题，稍后重试即可"
        case .network:
            "检查网络连接；如果用了代理，确认代理对该服务地址生效"
        case .malformedResponse:
            "如果用的是第三方 OpenAI 兼容服务，它的响应格式可能与标准有出入"
        case .notConfigured:
            "到「设置 → AI」添加一个服务商和 API Key"
        }
    }

    /// 重试有没有意义。
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .serverError, .network: true
        case .unauthorized, .forbidden, .notFound, .contextTooLong, .malformedResponse, .notConfigured:
            false
        }
    }

    /// 按 HTTP 状态码归类。两家协议的状态码语义一致，可以共用。
    static func fromStatus(_ status: Int, body: String, retryAfter: TimeInterval? = nil) -> AIError {
        let detail = Self.extractMessage(from: body) ?? body.prefix(200).description

        switch status {
        case 401: return .unauthorized(detail)
        case 403: return .forbidden(detail)
        case 404: return .notFound(detail)
        case 413: return .contextTooLong(detail)
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 400:
            // 上下文超长在两家都是 400，只能靠报文里的关键词区分
            let lowered = detail.lowercased()
            if lowered.contains("context") || lowered.contains("too long")
                || lowered.contains("maximum") || lowered.contains("token")
            {
                return .contextTooLong(detail)
            }
            return .serverError(status: status, message: detail)
        default:
            return .serverError(status: status, message: detail)
        }
    }

    /// 从错误响应体里挖出人话。
    ///
    /// 两家的错误结构不同（Anthropic 是 `{error:{message}}`，OpenAI 也是，但一些
    /// 兼容服务会塞成 `{message}` 或 `{error:"..."}`），逐个试一遍，都不中就原样返回。
    private static func extractMessage(from body: String) -> String? {
        guard
            let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = object["error"] as? String { return error }
        if let message = object["message"] as? String { return message }
        return nil
    }
}
