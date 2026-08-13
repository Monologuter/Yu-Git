import Foundation

/// 访问一个托管平台。
///
/// 三家的 REST API 差别不小（认证头、路径、字段名、状态表示法全不一样），
/// 所以按平台分派而不是硬凑一套通用参数。
public struct ForgeClient: Sendable {

    private let locator: RemoteLocator
    private let token: String
    private let session: URLSession

    public init(locator: RemoteLocator, token: String, session: URLSession = .shared) {
        self.locator = locator
        self.token = token
        self.session = session
    }

    public var kind: ForgeKind { locator.kind }

    // MARK: - 列表

    /// 列出 PR / MR。
    public func pullRequests(state: PullRequest.State? = .open, limit: Int = 30) async throws -> [PullRequest] {
        guard let base = locator.apiBaseURL else {
            throw ForgeError.unsupported("认不出这个主机的 API 地址")
        }

        switch locator.kind {
        case .github:
            let url = base.appending(path: "/repos/\(locator.fullPath)/pulls")
                .appending(queryItems: [
                    .init(name: "state", value: githubState(state)),
                    .init(name: "per_page", value: "\(limit)"),
                ])
            let data = try await send(url, method: "GET")
            return try decodeList(data, transform: GitHubPullRequest.toModel)

        case .gitee:
            // Gitee 的接口路径与 GitHub 一致，但认证方式和分页参数不同
            let url = base.appending(path: "/repos/\(locator.fullPath)/pulls")
                .appending(queryItems: [
                    .init(name: "state", value: githubState(state)),
                    .init(name: "per_page", value: "\(limit)"),
                ])
            let data = try await send(url, method: "GET")
            return try decodeList(data, transform: GitHubPullRequest.toModel)

        case .gitlab:
            let url = base.appending(path: "/projects/\(locator.urlEncodedPath)/merge_requests")
                .appending(queryItems: [
                    .init(name: "state", value: gitlabState(state)),
                    .init(name: "per_page", value: "\(limit)"),
                ])
            let data = try await send(url, method: "GET")
            return try decodeList(data, transform: GitLabMergeRequest.toModel)
        }
    }

    // MARK: - 创建

    /// 新建 PR / MR。
    @discardableResult
    public func createPullRequest(_ request: NewPullRequest) async throws -> PullRequest {
        guard let base = locator.apiBaseURL else {
            throw ForgeError.unsupported("认不出这个主机的 API 地址")
        }

        switch locator.kind {
        case .github, .gitee:
            var body: [String: Any] = [
                "title": request.title,
                "head": request.sourceBranch,
                "base": request.targetBranch,
                "body": request.body,
            ]
            // Gitee 不认 draft 字段，传了会被忽略；GitHub 认
            if locator.kind == .github, request.isDraft { body["draft"] = true }

            let url = base.appending(path: "/repos/\(locator.fullPath)/pulls")
            let data = try await send(url, method: "POST", body: body)
            return try decodeOne(data, transform: GitHubPullRequest.toModel)

        case .gitlab:
            var body: [String: Any] = [
                "title": request.isDraft ? "Draft: \(request.title)" : request.title,
                "source_branch": request.sourceBranch,
                "target_branch": request.targetBranch,
                "description": request.body,
            ]
            // GitLab 用标题前缀表示草稿，没有独立字段
            if request.isDraft { body["title"] = "Draft: \(request.title)" }

            let url = base.appending(path: "/projects/\(locator.urlEncodedPath)/merge_requests")
            let data = try await send(url, method: "POST", body: body)
            return try decodeOne(data, transform: GitLabMergeRequest.toModel)
        }
    }

    // MARK: - 状态映射

    private func githubState(_ state: PullRequest.State?) -> String {
        switch state {
        case .open: "open"
        case .closed, .merged: "closed"  // GitHub 把已合并算作 closed
        case nil: "all"
        }
    }

    private func gitlabState(_ state: PullRequest.State?) -> String {
        switch state {
        case .open: "opened"
        case .merged: "merged"
        case .closed: "closed"
        case nil: "all"
        }
    }

    // MARK: - HTTP

    private func send(_ url: URL, method: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "accept")

        // 三家的认证头各不相同，这是最容易搞错的一处
        switch locator.kind {
        case .github:
            request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
            // 不带这个头时 GitHub 可能返回旧版格式
            request.setValue("2022-11-28", forHTTPHeaderField: "x-github-api-version")
        case .gitlab:
            request.setValue(token, forHTTPHeaderField: "private-token")
        case .gitee:
            request.setValue("token \(token)", forHTTPHeaderField: "authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ForgeError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ForgeError.malformedResponse("不是 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let retryAfter = http.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
            throw ForgeError.fromStatus(
                http.statusCode,
                body: String(decoding: data, as: UTF8.self),
                retryAfter: retryAfter
            )
        }

        return data
    }

    // MARK: - 解码

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // 三家都用 ISO8601，但 GitLab 带毫秒
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw ForgeError.malformedResponse("认不出的时间格式：\(text)")
        }
        return decoder
    }()

    private func decodeList<Raw: Decodable>(
        _ data: Data,
        transform: (Raw) -> PullRequest
    ) throws -> [PullRequest] {
        do {
            return try Self.decoder.decode([Raw].self, from: data).map(transform)
        } catch {
            throw ForgeError.malformedResponse(String(String(decoding: data, as: UTF8.self).prefix(200)))
        }
    }

    private func decodeOne<Raw: Decodable>(
        _ data: Data,
        transform: (Raw) -> PullRequest
    ) throws -> PullRequest {
        do {
            return transform(try Self.decoder.decode(Raw.self, from: data))
        } catch {
            throw ForgeError.malformedResponse(String(String(decoding: data, as: UTF8.self).prefix(200)))
        }
    }
}
