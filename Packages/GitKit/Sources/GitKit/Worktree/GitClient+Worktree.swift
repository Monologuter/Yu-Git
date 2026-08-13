import Foundation

/// 一个 worktree 加上它当前的工作状态。
///
/// 并行 agent 面板要一眼看出「哪个还在改、哪个可以合了」，
/// 所以列表之外还得带上改动数和领先/落后。
public struct WorktreeStatus: Sendable, Equatable, Identifiable {

    public var id: String { worktree.path }

    public let worktree: Worktree
    /// 未提交的改动文件数。
    public let dirtyFileCount: Int
    /// 相对基线分支领先几条。
    public let ahead: Int
    /// 相对基线分支落后几条。
    public let behind: Int
    /// 最近一条提交的标题。
    public let lastCommitSubject: String?

    public var isClean: Bool { dirtyFileCount == 0 }

    /// 可以合回去了：有东西可合，且工作区干净。
    public var isReadyToMerge: Bool { ahead > 0 && isClean }

    public init(
        worktree: Worktree,
        dirtyFileCount: Int,
        ahead: Int,
        behind: Int,
        lastCommitSubject: String?
    ) {
        self.worktree = worktree
        self.dirtyFileCount = dirtyFileCount
        self.ahead = ahead
        self.behind = behind
        self.lastCommitSubject = lastCommitSubject
    }
}

extension GitClient {

    // MARK: - 查询

    /// 列出所有 worktree。
    public func worktrees(in repository: URL) async throws -> [Worktree] {
        let result = try await run(
            ["worktree", "list", "--porcelain", "-z"],
            in: repository,
            allowsOptionalLocks: false
        )
        return WorktreeParser.parse(result.standardOutput)
    }

    /// 列出 worktree 并带上各自的工作状态。
    ///
    /// 每个 worktree 都要单独跑几条 git，所以并发发出去——串行的话
    /// 五个 worktree 就要等五轮，面板打开会有明显停顿。
    public func worktreeStatuses(
        in repository: URL,
        comparedTo baseline: String
    ) async throws -> [WorktreeStatus] {
        let list = try await worktrees(in: repository)

        return await withTaskGroup(of: (Int, WorktreeStatus).self) { group in
            for (index, worktree) in list.enumerated() {
                group.addTask {
                    (index, await self.status(of: worktree, comparedTo: baseline))
                }
            }

            var collected: [(Int, WorktreeStatus)] = []
            for await item in group { collected.append(item) }
            // 并发收回来的顺序是乱的，按原顺序排回去——主 worktree 得在第一个
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func status(of worktree: Worktree, comparedTo baseline: String) async -> WorktreeStatus {
        let url = URL(fileURLWithPath: worktree.path, isDirectory: true)

        // 目录可能已经被人删了（prunable），此时所有查询都会失败，
        // 但这条 worktree 仍然要出现在列表里——不然用户不知道该去清理它
        async let dirty = (try? self.status(of: url))?.entries.count ?? 0
        async let counts = self.aheadBehind(of: url, versus: baseline)
        async let subject = (try? self.recentSubjects(in: url, limit: 1))?.first

        return WorktreeStatus(
            worktree: worktree,
            dirtyFileCount: await dirty,
            ahead: await counts.ahead,
            behind: await counts.behind,
            lastCommitSubject: await subject
        )
    }

    /// 相对某个基线领先/落后多少条。
    private func aheadBehind(of repository: URL, versus baseline: String) async -> (ahead: Int, behind: Int) {
        // 一条命令同时拿两个数字，输出形如 "3\t1"（左边是落后，右边是领先）
        guard
            let result = try? await runReturningResult(
                ["rev-list", "--left-right", "--count", "\(baseline)...HEAD"],
                in: repository
            ),
            result.isSuccess
        else { return (0, 0) }

        let parts = result.standardOutputText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .compactMap { Int($0) }

        guard parts.count == 2 else { return (0, 0) }
        return (ahead: parts[1], behind: parts[0])
    }

    // MARK: - 增删

    /// 新建一个 worktree。
    ///
    /// - Parameters:
    ///   - path: 新工作目录的位置。**不能在仓库目录里面**——那会让工作区多出一个
    ///     未跟踪的大目录，还可能被自己递归收进去。
    ///   - branch: 要签出的分支。
    ///   - createBranch: 为 true 时新建这个分支（`-b`），否则要求它已存在。
    public func addWorktree(
        at path: URL,
        branch: String,
        createBranch: Bool,
        from startPoint: String? = nil,
        in repository: URL
    ) async throws {
        var arguments = ["worktree", "add"]
        if createBranch {
            arguments += ["-b", branch]
        }
        arguments.append(path.path(percentEncoded: false))
        if createBranch {
            if let startPoint { arguments.append(startPoint) }
        } else {
            arguments.append(branch)
        }

        _ = try await run(arguments, in: repository)
    }

    /// 移除一个 worktree。
    ///
    /// - Parameter force: 工作区还有未提交改动时也照删。这会**丢掉那些改动**，
    ///   界面上必须先问清楚。
    public func removeWorktree(at path: String, force: Bool, in repository: URL) async throws {
        var arguments = ["worktree", "remove"]
        if force { arguments.append("--force") }
        arguments.append(path)

        _ = try await run(arguments, in: repository)
    }

    /// 锁定，避免被 prune 清掉。
    public func lockWorktree(at path: String, reason: String?, in repository: URL) async throws {
        var arguments = ["worktree", "lock"]
        if let reason, !reason.isEmpty { arguments += ["--reason", reason] }
        arguments.append(path)

        _ = try await run(arguments, in: repository)
    }

    public func unlockWorktree(at path: String, in repository: URL) async throws {
        _ = try await run(["worktree", "unlock", path], in: repository)
    }

    /// 清理那些目录已经不存在的 worktree 记录。
    public func pruneWorktrees(in repository: URL) async throws {
        _ = try await run(["worktree", "prune"], in: repository)
    }
}
