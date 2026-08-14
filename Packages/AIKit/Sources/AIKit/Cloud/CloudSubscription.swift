import Foundation

/// 驭Git 云服务的订阅状态。
///
/// 商业模式的边界（PRD §6）：**本地 Git 全功能永久免费**，云服务只对
/// 「有边际成本的东西」收费，也就是 AI 推理本身。不订阅照样能用全部
/// 本地功能，也照样能自带 Key 用全部 AI 功能。
public struct CloudSubscription: Sendable, Equatable, Codable {

    public enum Status: String, Sendable, Equatable, Codable {
        /// 没有订阅。
        case none
        /// 生效中。
        case active
        /// 过期了，续费即可恢复。
        case expired
        /// 服务端说这个凭据有问题。
        case invalid

        public var displayName: String {
            switch self {
            case .none: "未订阅"
            case .active: "订阅中"
            case .expired: "已过期"
            case .invalid: "凭据无效"
            }
        }
    }

    public let status: Status
    /// 本周期还剩多少 token 额度。服务端不报时为 nil。
    public let remainingTokens: Int?
    /// 本周期的总额度。
    public let totalTokens: Int?
    /// 下次续期时间。
    public let renewsAt: Date?
    /// 服务端想让客户端显示的一句话（例如「额度不足，本月已用尽」）。
    public let message: String?

    public init(
        status: Status,
        remainingTokens: Int? = nil,
        totalTokens: Int? = nil,
        renewsAt: Date? = nil,
        message: String? = nil
    ) {
        self.status = status
        self.remainingTokens = remainingTokens
        self.totalTokens = totalTokens
        self.renewsAt = renewsAt
        self.message = message
    }

    public static let none = CloudSubscription(status: .none)

    public var isUsable: Bool {
        status == .active && (remainingTokens ?? 1) > 0
    }

    /// 已用额度占比（0…1）。算不出来时为 nil。
    public var usedRatio: Double? {
        guard let total = totalTokens, total > 0, let remaining = remainingTokens else { return nil }
        return Double(total - remaining) / Double(total)
    }
}

/// 驭Git 云服务。
///
/// 协议上是 OpenAI 兼容的一个变体——**刻意如此**：自建一套私有协议
/// 除了增加维护面之外没有任何好处，而复用已有的兼容层意味着云服务
/// 与用户自带 Key 走的是同一条经过测试的代码路径。
///
/// - Important: 服务端尚未上线。这里的实现是完整的客户端侧，
///   端点可配置，界面上会如实标注「服务尚未开放」而不是假装能用。
public struct YugitCloudProvider: AIProvider {

    /// 默认端点。
    public static let defaultEndpoint: URL = .literal("https://yugit.educy.top/v1")

    /// 服务是否已经上线。
    ///
    /// 写成常量而不是靠探测：探测失败和网络故障长得一模一样，
    /// 用户会以为是自己的网络问题而反复重试。
    ///
    /// - Note: 网关本身已经部署并跑通（含流式与计费），但 TLS 还没配上——
    ///   证书签发要求 80 端口从公网可达，而云厂商的安全组默认不放行。
    ///   在拿到 https 之前不翻开这个开关：订阅凭据走明文 HTTP 传输，
    ///   等于把用户的付费凭据摆在网上。宁可显示「尚未开放」。
    public static let isServiceAvailable = false

    public let displayName = "驭Git 云服务"

    private let credential: String
    private let endpoint: URL
    private let inner: OpenAICompatibleProvider
    private let transport: HTTPTransport

    public init(
        credential: String,
        endpoint: URL = YugitCloudProvider.defaultEndpoint,
        session: URLSession = .shared
    ) {
        self.credential = credential
        self.endpoint = endpoint
        self.inner = OpenAICompatibleProvider(
            apiKey: credential,
            baseURL: endpoint,
            displayName: "驭Git 云服务",
            session: session
        )
        self.transport = HTTPTransport(session: session)
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIStreamEvent, any Error> {
        inner.stream(request)
    }

    public func validateCredentials() async throws {
        _ = try await subscription()
    }

    /// 查询订阅状态与剩余额度。
    public func subscription() async throws -> CloudSubscription {
        var request = URLRequest(url: endpoint.appending(path: "subscription"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.timeoutInterval = 20

        let data = try await transport.send(request)

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CloudSubscription.self, from: data)
        } catch {
            throw AIError.malformedResponse(String(String(decoding: data, as: UTF8.self).prefix(200)))
        }
    }

    /// 云服务提供的模型。
    ///
    /// 固定一份清单而不是让用户填：订阅制下用户付的是「按量的推理费」，
    /// 能用哪些模型由服务端决定，让用户填一个服务端不认的名字只会白报错。
    public static let models: [AIModelPresets.Suggestion] = [
        .init(id: "yugit-standard", displayName: "标准", note: "日常够用，额度消耗最低"),
        .init(id: "yugit-pro", displayName: "增强", note: "复杂改动的解释和评审更准，消耗更多额度"),
    ]
}
