import Foundation

/// 不打开仓库就能知道的一点信息。
///
/// 用来给「最近打开」列表配上「它现在在哪个分支」。为此各开一次仓库
/// （建 `RepoActor`、拉起 git 进程、读 status）太贵——十个仓库就是十次进程启动，
/// 而这个列表可能只是被扫一眼。
public struct RepositoryGlance: Sendable, Equatable {

    public let url: URL
    /// 当前分支名。detached HEAD 时为 nil。
    public let branch: String?
    /// 是不是 detached HEAD。
    public let isDetached: Bool

    public var name: String { url.lastPathComponent }

    public init(url: URL, branch: String?, isDetached: Bool) {
        self.url = url
        self.branch = branch
        self.isDetached = isDetached
    }

    /// 直接读 `.git/HEAD`，不起 git 进程。
    ///
    /// 那个文件只有几十字节，内容是两种形态之一：
    /// ```
    /// ref: refs/heads/main     ← 在某个分支上
    /// 4d7a214614ab2935…        ← detached HEAD，直接是一个 hash
    /// ```
    /// 读不到（目录被删了、或者根本不是仓库）时返回 nil，由调用方决定怎么办——
    /// 「最近打开」列表里出现一个已经被删掉的仓库是很正常的事。
    ///
    /// - Note: worktree 和 submodule 里的 `.git` 是**文件**而不是目录，
    ///   内容是 `gitdir: <路径>`。这里只处理常规仓库，其余返回 nil——
    ///   猜错分支名比不显示更糟。
    public static func read(at url: URL) -> RepositoryGlance? {
        let head = url.appendingPathComponent(".git/HEAD")
        guard let contents = try? String(contentsOf: head, encoding: .utf8) else { return nil }

        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let refPrefix = "ref: refs/heads/"
        if trimmed.hasPrefix(refPrefix) {
            let branch = String(trimmed.dropFirst(refPrefix.count))
            return RepositoryGlance(url: url, branch: branch, isDetached: false)
        }

        // 不是 `ref:` 开头就是一个裸 hash，即 detached HEAD。
        // 但也可能是 `ref: refs/tags/...` 这类非分支引用，那同样不是分支。
        if trimmed.hasPrefix("ref: ") {
            return RepositoryGlance(url: url, branch: nil, isDetached: false)
        }
        return RepositoryGlance(url: url, branch: nil, isDetached: true)
    }
}
