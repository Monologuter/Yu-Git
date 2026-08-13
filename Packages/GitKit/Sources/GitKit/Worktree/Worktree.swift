import Foundation

/// 一个 worktree。
///
/// 同一个仓库可以同时签出多个分支到不同目录，各干各的互不打扰。
/// 这是并行跑多个 agent 的基础设施：每个 agent 一个 worktree，
/// 谁也不会把谁的工作区搅乱。
public struct Worktree: Sendable, Equatable, Identifiable {

    public var id: String { path }

    /// 工作目录的绝对路径。
    public let path: String
    /// HEAD 指向的 commit。裸仓库为 nil。
    public let head: String?
    /// 签出的分支名（已去掉 `refs/heads/` 前缀）。detached 或裸仓库为 nil。
    public let branch: String?

    /// 主 worktree（仓库本身）。它不能被移除。
    public let isMain: Bool
    public let isBare: Bool
    public let isDetached: Bool

    /// 被锁定的原因。非 nil 即表示锁定——锁定的 worktree 不会被 `prune` 清掉，
    /// 常用于放在移动硬盘上的副本。
    public let lockReason: String?
    /// git 认为它可以被清理的原因（目录已经不在了之类）。
    public let prunableReason: String?

    public var isLocked: Bool { lockReason != nil }
    public var isPrunable: Bool { prunableReason != nil }

    /// 目录名，界面上比全路径好认。
    public var displayName: String {
        (path as NSString).lastPathComponent
    }

    public init(
        path: String,
        head: String? = nil,
        branch: String? = nil,
        isMain: Bool = false,
        isBare: Bool = false,
        isDetached: Bool = false,
        lockReason: String? = nil,
        prunableReason: String? = nil
    ) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isMain = isMain
        self.isBare = isBare
        self.isDetached = isDetached
        self.lockReason = lockReason
        self.prunableReason = prunableReason
    }
}

/// 解析 `git worktree list --porcelain -z`。
public enum WorktreeParser {

    /// 解析输出。
    ///
    /// 必须用 `-z`：不带它的时候，git 会把中文路径、中文分支名、中文锁定原因
    /// 全部按 C 风格转义成 `\350\267\221` 这样的八进制串——中文用户的仓库里
    /// 这三样都很常见。`-z` 下一律原样输出，条目之间以两个 NUL 分隔。
    public static func parse(_ data: Data) -> [Worktree] {
        // 按 NUL 切成一行行。条目之间是空行（连续两个 NUL）。
        let fields = data.split(separator: 0x00, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }

        var worktrees: [Worktree] = []
        var current: [String: String] = [:]
        var flags: Set<String> = []

        func flush() {
            defer {
                current.removeAll()
                flags.removeAll()
            }
            guard let path = current["worktree"] else { return }

            worktrees.append(
                Worktree(
                    path: path,
                    head: current["HEAD"],
                    // git 给的是全名 refs/heads/xxx，界面上要短名
                    branch: current["branch"].map { $0.replacingOccurrences(of: "refs/heads/", with: "") },
                    // 第一条永远是主 worktree，git 保证这个顺序
                    isMain: worktrees.isEmpty,
                    isBare: flags.contains("bare"),
                    isDetached: flags.contains("detached"),
                    // 无原因的锁定也是锁定，所以用空串而不是 nil 表示
                    lockReason: flags.contains("locked") ? (current["locked"] ?? "") : nil,
                    prunableReason: flags.contains("prunable") ? (current["prunable"] ?? "") : nil
                ))
        }

        for line in fields {
            guard !line.isEmpty else {
                flush()
                continue
            }

            // `worktree <path>`、`HEAD <sha>`、`branch <ref>`、`locked [reason]`、
            // `prunable [reason]`、`bare`、`detached`
            if let space = line.firstIndex(of: " ") {
                let key = String(line[line.startIndex..<space])
                let value = String(line[line.index(after: space)...])
                current[key] = value
                flags.insert(key)
            } else {
                flags.insert(line)
            }
        }
        flush()

        return worktrees
    }
}
