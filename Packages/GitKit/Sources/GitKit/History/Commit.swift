import Foundation

/// 一条 commit 的元数据。
///
/// 不含 diff——历史列表只需要这些字段就能渲染，diff 按需单独取。
/// 5 万 commit 的仓库要在 500ms 内出首屏，这个结构必须保持精简。
public struct Commit: Sendable, Equatable, Identifiable {

    public var id: String { hash }

    public let hash: String
    /// git 计算的缩写 hash，长度随仓库规模自动变化，不要自己截断。
    public let abbreviatedHash: String
    /// 父提交。空表示根提交，多于一个表示合并提交。
    public let parents: [String]

    public let author: Signature
    public let committer: Signature

    /// commit message 的第一行。
    public let subject: String
    /// commit message 除第一行外的部分，已去除首尾空行。
    public let body: String

    /// 指向这条 commit 的引用（分支、tag、HEAD）。
    public let refs: [CommitRef]

    public var isMerge: Bool { parents.count > 1 }
    public var isRoot: Bool { parents.isEmpty }

    /// 完整的 commit message。
    public var message: String {
        body.isEmpty ? subject : "\(subject)\n\n\(body)"
    }

    public init(
        hash: String,
        abbreviatedHash: String,
        parents: [String],
        author: Signature,
        committer: Signature,
        subject: String,
        body: String,
        refs: [CommitRef]
    ) {
        self.hash = hash
        self.abbreviatedHash = abbreviatedHash
        self.parents = parents
        self.author = author
        self.committer = committer
        self.subject = subject
        self.body = body
        self.refs = refs
    }
}

/// 提交者/作者署名。
///
/// git 区分 author（写代码的人）与 committer（提交的人）：cherry-pick、rebase、
/// amend 都会让两者分离，历史界面需要能显示这个差异。
public struct Signature: Sendable, Equatable {
    public let name: String
    public let email: String
    public let date: Date

    public init(name: String, email: String, date: Date) {
        self.name = name
        self.email = email
        self.date = date
    }
}

/// 指向某条 commit 的引用。
public enum CommitRef: Sendable, Equatable {
    /// HEAD 本身（detached 时单独出现）。
    case head
    /// 本地分支。
    case localBranch(String)
    /// 远程跟踪分支，如 `origin/main`。
    case remoteBranch(String)
    case tag(String)
    /// stash、notes 等其他引用，保留原始全名。
    case other(String)

    /// 界面上显示的短名称。
    public var displayName: String {
        switch self {
        case .head: "HEAD"
        case let .localBranch(name), let .remoteBranch(name), let .tag(name): name
        case let .other(name): name
        }
    }
}
