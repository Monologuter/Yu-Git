import Foundation

/// GitHub / Gitee 的 PR 结构。两家的字段名一致，共用一份。
struct GitHubPullRequest: Decodable {

    let number: Int
    let title: String
    let state: String
    /// 已合并的时间。GitHub 把已合并的 PR 也报成 `state: "closed"`，
    /// **只能靠这个字段区分「合并了」和「关掉了」**——两者对用户的意义完全不同。
    let mergedAt: Date?
    let draft: Bool?
    let htmlUrl: String?
    let createdAt: Date?
    let user: User?
    let head: Ref?
    let base: Ref?

    struct User: Decodable {
        let login: String?
        /// Gitee 用 name 放中文昵称，login 放英文 ID
        let name: String?
    }

    struct Ref: Decodable {
        let ref: String?
    }

    static func toModel(_ raw: GitHubPullRequest) -> PullRequest {
        let state: PullRequest.State =
            if raw.mergedAt != nil {
                .merged
            } else if raw.state == "open" {
                .open
            } else {
                .closed
            }

        return PullRequest(
            number: raw.number,
            title: raw.title,
            state: state,
            authorName: raw.user?.name ?? raw.user?.login ?? "",
            sourceBranch: raw.head?.ref ?? "",
            targetBranch: raw.base?.ref ?? "",
            webURL: raw.htmlUrl.flatMap(URL.init(string:)),
            createdAt: raw.createdAt,
            isDraft: raw.draft ?? false
        )
    }
}

/// GitLab 的 MR 结构。
struct GitLabMergeRequest: Decodable {

    /// 项目内编号。**不要用 `id`**——那是 GitLab 全局唯一的内部 id，
    /// 和界面上显示的 `!123` 对不上。
    let iid: Int
    let title: String
    let state: String
    let draft: Bool?
    /// 老版本 GitLab 用 work_in_progress 表示草稿
    let workInProgress: Bool?
    let webUrl: String?
    let createdAt: Date?
    let author: Author?
    let sourceBranch: String?
    let targetBranch: String?

    struct Author: Decodable {
        let name: String?
        let username: String?
    }

    static func toModel(_ raw: GitLabMergeRequest) -> PullRequest {
        let state: PullRequest.State =
            switch raw.state {
            case "opened": .open
            case "merged": .merged
            default: .closed
            }

        return PullRequest(
            number: raw.iid,
            title: raw.title,
            state: state,
            authorName: raw.author?.name ?? raw.author?.username ?? "",
            sourceBranch: raw.sourceBranch ?? "",
            targetBranch: raw.targetBranch ?? "",
            webURL: raw.webUrl.flatMap(URL.init(string:)),
            createdAt: raw.createdAt,
            isDraft: raw.draft ?? raw.workInProgress ?? false
        )
    }
}
