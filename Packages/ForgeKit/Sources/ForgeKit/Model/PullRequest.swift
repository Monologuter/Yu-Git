import Foundation

/// 一个 PR / MR。三家平台的字段名不同，统一成这个形状。
public struct PullRequest: Sendable, Equatable, Identifiable {

    public enum State: String, Sendable, Equatable {
        case open
        case merged
        case closed

        public var displayName: String {
            switch self {
            case .open: "进行中"
            case .merged: "已合并"
            case .closed: "已关闭"
            }
        }
    }

    /// 平台内的编号（`#123` 里的 123）。用它而不是内部 id：
    /// 界面上要显示的、用户口头说的，都是这个号。
    public let number: Int
    public var id: Int { number }

    public let title: String
    public let state: State
    public let authorName: String
    public let sourceBranch: String
    public let targetBranch: String
    public let webURL: URL?
    public let createdAt: Date?
    /// 是否为草稿。
    public let isDraft: Bool

    public init(
        number: Int,
        title: String,
        state: State,
        authorName: String,
        sourceBranch: String,
        targetBranch: String,
        webURL: URL?,
        createdAt: Date?,
        isDraft: Bool = false
    ) {
        self.number = number
        self.title = title
        self.state = state
        self.authorName = authorName
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.webURL = webURL
        self.createdAt = createdAt
        self.isDraft = isDraft
    }
}

/// 新建 PR / MR 的参数。
public struct NewPullRequest: Sendable, Equatable {

    public let title: String
    public let body: String
    public let sourceBranch: String
    public let targetBranch: String
    public let isDraft: Bool

    public init(
        title: String,
        body: String = "",
        sourceBranch: String,
        targetBranch: String,
        isDraft: Bool = false
    ) {
        self.title = title
        self.body = body
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.isDraft = isDraft
    }
}

/// 平台调用失败的分类。
public enum ForgeError: Error, Sendable, Equatable {

    case notConfigured
    case unauthorized
    case forbidden(String)
    case notFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case unsupported(String)
    case serverError(status: Int, message: String)
    case network(String)
    case malformedResponse(String)

    public var localizedMessage: String {
        switch self {
        case .notConfigured: "还没有配置这个平台的访问令牌"
        case .unauthorized: "访问令牌无效或已过期"
        case let .forbidden(detail): "没有权限：\(detail)"
        case let .notFound(detail): "找不到资源：\(detail)"
        case .rateLimited: "请求太频繁，被平台限流了"
        case let .unsupported(detail): "暂不支持：\(detail)"
        case let .serverError(status, message): "平台返回错误（\(status)）：\(message)"
        case let .network(detail): "网络连接失败：\(detail)"
        case let .malformedResponse(detail): "响应解析失败：\(detail)"
        }
    }

    public var suggestion: String {
        switch self {
        case .notConfigured:
            "到「设置 → 平台」为这个主机添加访问令牌"
        case .unauthorized:
            "令牌可能已过期或被撤销，重新生成一个再填进来"
        case .forbidden:
            "确认令牌的权限范围包含仓库读写（GitHub 需要 repo，GitLab 需要 api）"
        case .notFound:
            "确认仓库路径正确，以及令牌对这个仓库有访问权"
        case let .rateLimited(retryAfter):
            if let seconds = retryAfter {
                "等待约 \(Int(seconds)) 秒后重试"
            } else {
                "稍后重试"
            }
        case .unsupported:
            "可以在浏览器里完成这一步"
        case .serverError:
            "这是平台侧的问题，稍后重试即可"
        case .network:
            "检查网络连接；自建实例还要确认域名可达"
        case .malformedResponse:
            "自建实例的 API 版本可能与预期不一致"
        }
    }

    public var isTransient: Bool {
        switch self {
        case .rateLimited, .serverError, .network: true
        default: false
        }
    }

    static func fromStatus(_ status: Int, body: String, retryAfter: TimeInterval? = nil) -> ForgeError {
        let detail = extractMessage(from: body) ?? String(body.prefix(200))

        switch status {
        case 401: return .unauthorized
        case 403:
            // GitHub 用 403 同时表示「没权限」和「被限流」，靠报文区分
            if detail.lowercased().contains("rate limit") {
                return .rateLimited(retryAfter: retryAfter)
            }
            return .forbidden(detail)
        case 404: return .notFound(detail)
        case 429: return .rateLimited(retryAfter: retryAfter)
        default: return .serverError(status: status, message: detail)
        }
    }

    /// 三家的错误结构不同，逐个试。
    private static func extractMessage(from body: String) -> String? {
        guard
            let data = body.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // GitHub / Gitee: {"message": "..."}；GitLab: {"message": {...}} 或 {"error": "..."}
        if let message = object["message"] as? String { return message }
        if let error = object["error"] as? String { return error }
        if let error = object["error_description"] as? String { return error }
        if let nested = object["message"] as? [String: Any] {
            return nested.map { "\($0.key): \($0.value)" }.sorted().joined(separator: "；")
        }
        if let list = object["message"] as? [String] { return list.joined(separator: "；") }
        return nil
    }
}
