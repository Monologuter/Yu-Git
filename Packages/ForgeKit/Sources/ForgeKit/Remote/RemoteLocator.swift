import Foundation

/// 托管平台的种类。
public enum ForgeKind: String, Sendable, Equatable, Codable, CaseIterable {
    case github
    case gitlab
    case gitee

    public var displayName: String {
        switch self {
        case .github: "GitHub"
        case .gitlab: "GitLab"
        case .gitee: "码云 Gitee"
        }
    }

    /// 这个平台把「合并请求」叫什么。GitHub 叫 PR，GitLab 叫 MR，
    /// 界面上要跟着平台的叫法走，否则用户对不上号。
    public var requestNoun: String {
        switch self {
        case .github, .gitee: "Pull Request"
        case .gitlab: "Merge Request"
        }
    }

    public var shortNoun: String {
        switch self {
        case .github, .gitee: "PR"
        case .gitlab: "MR"
        }
    }
}

/// 从 remote URL 认出来的仓库坐标。
public struct RemoteLocator: Sendable, Equatable {

    public let kind: ForgeKind
    /// 主机名，例如 `github.com` 或自建的 `gitlab.mycorp.cn`。
    public let host: String
    /// 仓库的完整路径。GitLab 允许嵌套 group，所以可能是 `组/子组/仓库`。
    public let fullPath: String

    /// 拥有者部分（GitLab 嵌套时是除最后一段之外的全部）。
    public var owner: String {
        let parts = fullPath.split(separator: "/")
        return parts.dropLast().joined(separator: "/")
    }

    public var name: String {
        String(fullPath.split(separator: "/").last ?? "")
    }

    public init(kind: ForgeKind, host: String, fullPath: String) {
        self.kind = kind
        self.host = host
        self.fullPath = fullPath
    }

    // MARK: - 解析

    /// 从 remote URL 认出平台与仓库路径。
    ///
    /// 要认的形式比想象中多：
    /// - `https://github.com/owner/repo.git`
    /// - `git@github.com:owner/repo.git`（scp 语法，**不是合法 URL**，得单独拆）
    /// - `ssh://git@gitlab.example.com:2222/group/sub/repo.git`（带端口）
    /// - `https://user:token@gitlab.example.com/group/repo.git`（URL 里带凭据）
    public static func parse(remoteURL: String) -> RemoteLocator? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let (host, path) = splitHostAndPath(trimmed) else { return nil }
        guard let kind = detectKind(host: host) else { return nil }

        let cleanPath = normalize(path: path)
        guard cleanPath.contains("/") else { return nil }

        return RemoteLocator(kind: kind, host: host, fullPath: cleanPath)
    }

    /// 拆出主机名和路径。
    static func splitHostAndPath(_ url: String) -> (host: String, path: String)? {
        // scp 语法 `git@host:path`。它长得像 URL 但不是——`URL(string:)` 会把
        // `github.com:owner/repo.git` 整个当成路径，解析出来的 host 是 nil。
        // 判据：有冒号、冒号后面不是 `//`，且冒号之前没有 `/`。
        if let colon = url.firstIndex(of: ":"),
            !url[url.index(after: colon)...].hasPrefix("//"),
            !url[url.startIndex..<colon].contains("/")
        {
            var authority = String(url[url.startIndex..<colon])
            // 去掉 `git@` 这样的用户名
            if let at = authority.lastIndex(of: "@") {
                authority = String(authority[authority.index(after: at)...])
            }
            let path = String(url[url.index(after: colon)...])
            guard !authority.isEmpty else { return nil }
            return (authority.lowercased(), path)
        }

        guard let parsed = URL(string: url), let host = parsed.host() else { return nil }
        // path() 默认返回 percent-encoded 形式，中文仓库路径会变成一串 %E7%BB%84。
        // GitLab 上中文 group 名并不罕见，这里要拿解码后的原文。
        return (host.lowercased(), parsed.path(percentEncoded: false))
    }

    /// 按主机名判断平台。
    ///
    /// 自建实例的域名千奇百怪，认不出来时默认按 GitLab 算——自建 GitLab
    /// 远比自建 GitHub Enterprise 或 Gitee 常见，而且它的 API 用 token
    /// 就能访问，猜错的代价只是一次 401。
    static func detectKind(host: String) -> ForgeKind? {
        if host == "github.com" || host.hasSuffix(".github.com") { return .github }
        if host == "gitee.com" || host.hasSuffix(".gitee.com") { return .gitee }
        if host == "gitlab.com" || host.hasSuffix(".gitlab.com") { return .gitlab }

        // 域名里带 github / gitlab 字样的自建实例
        if host.contains("github") { return .github }
        if host.contains("gitlab") { return .gitlab }

        return nil
    }

    /// 去掉前导斜杠和 `.git` 后缀。
    static func normalize(path: String) -> String {
        var value = path
        while value.hasPrefix("/") { value.removeFirst() }
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        return value
    }

    // MARK: - 地址

    /// API 根地址。
    public var apiBaseURL: URL? {
        switch kind {
        case .github:
            // GitHub Enterprise 的 API 在 /api/v3 下，github.com 用独立域名
            host == "github.com"
                ? URL(string: "https://api.github.com")
                : URL(string: "https://\(host)/api/v3")
        case .gitlab:
            URL(string: "https://\(host)/api/v4")
        case .gitee:
            URL(string: "https://gitee.com/api/v5")
        }
    }

    /// 在浏览器里打开仓库主页。
    public var webURL: URL? {
        URL(string: "https://\(host)/\(fullPath)")
    }

    /// GitLab 的 API 用 URL 编码后的完整路径当项目 ID。
    var urlEncodedPath: String {
        fullPath.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? fullPath
    }
}
