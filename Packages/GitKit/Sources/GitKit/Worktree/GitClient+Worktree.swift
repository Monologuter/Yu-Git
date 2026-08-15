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
    /// 这个 worktree 上最近一次被记下来的 AI 会话。
    ///
    /// 来源是私有 notes `refs/yugit/ai-sessions`，写入口是 MCP 工具 `yugit_attribute`。
    /// 没有记录时就是 nil——**不猜**。提交信息里本来就没有会话信息，
    /// 从「作者是 Claude」推断出一个会话来只会让人当真。
    public let session: AISession?

    public var isClean: Bool { dirtyFileCount == 0 }

    /// 可以合回去了：有东西可合，且工作区干净。
    public var isReadyToMerge: Bool { ahead > 0 && isClean }

    public init(
        worktree: Worktree,
        dirtyFileCount: Int,
        ahead: Int,
        behind: Int,
        lastCommitSubject: String?,
        session: AISession? = nil
    ) {
        self.worktree = worktree
        self.dirtyFileCount = dirtyFileCount
        self.ahead = ahead
        self.behind = behind
        self.lastCommitSubject = lastCommitSubject
        self.session = session
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
    public func worktreeStatuses(
        in repository: URL,
        comparedTo baseline: String
    ) async throws -> [WorktreeStatus] {
        try await worktreeOverview(in: repository, comparedTo: baseline).statuses
    }

    /// 列出 worktree、各自的状态，以及它们碰过的文件。
    ///
    /// 每个 worktree 都要单独跑几条 git，所以并发发出去——串行的话
    /// 五个 worktree 就要等五轮，面板打开会有明显停顿。
    public func worktreeOverview(
        in repository: URL,
        comparedTo baseline: String
    ) async throws -> WorktreeOverview {
        let list = try await worktrees(in: repository)
        // 会话记在私有 notes 里，而所有 worktree 共用同一个对象库，
        // 所以整个仓库读一次就够了，不必每个 worktree 各读一遍
        let sessions = await sessions(in: repository)

        let collected = await withTaskGroup(of: (Int, WorktreeStatus, Set<String>).self) { group in
            for (index, worktree) in list.enumerated() {
                group.addTask {
                    let (status, touched) = await self.inspect(
                        worktree, comparedTo: baseline, sessions: sessions)
                    return (index, status, touched)
                }
            }

            var results: [(Int, WorktreeStatus, Set<String>)] = []
            for await item in group { results.append(item) }
            // 并发收回来的顺序是乱的，按原顺序排回去——主 worktree 得在第一个
            return results.sorted { $0.0 < $1.0 }
        }

        return WorktreeOverview(
            statuses: collected.map(\.1),
            touchedPaths: Dictionary(
                uniqueKeysWithValues: collected.map { ($0.1.worktree.path, $0.2) })
        )
    }

    private func inspect(
        _ worktree: Worktree,
        comparedTo baseline: String,
        sessions: [String: AISession]
    ) async -> (WorktreeStatus, Set<String>) {
        let url = URL(fileURLWithPath: worktree.path, isDirectory: true)

        // 目录可能已经被人删了（prunable），此时所有查询都会失败，
        // 但这条 worktree 仍然要出现在列表里——不然用户不知道该去清理它
        async let status = try? self.status(of: url)
        async let counts = self.aheadBehind(of: url, versus: baseline)
        async let subject = (try? self.recentSubjects(in: url, limit: 1))?.first
        async let committed = self.pathsChanged(in: url, since: baseline)
        async let session = self.latestSession(in: url, since: baseline, among: sessions)

        let entries = await status?.entries ?? []
        // 改名的两个名字都要算：A 把 f 改名成 g、B 还在改 f，合的时候一样会撞，
        // 而只记新名字的话这一对根本对不上
        var touched = Set(entries.flatMap { [$0.path, $0.originalPath].compactMap { $0 } })
        touched.formUnion(await committed)

        return (
            WorktreeStatus(
                worktree: worktree,
                dirtyFileCount: entries.count,
                ahead: await counts.ahead,
                behind: await counts.behind,
                lastCommitSubject: await subject,
                session: await session
            ),
            touched
        )
    }

    /// 这个 worktree 相对基线**已经提交**的改动碰了哪些文件。
    private func pathsChanged(in repository: URL, since baseline: String) async -> Set<String> {
        // 三点：从共同祖先算起我这边改了什么。两点会把基线那边的改动也算进来，
        // 那些不是这个 worktree 干的。
        guard
            let result = try? await runReturningResult(
                ["diff", "--name-status", "-z", "-M", "\(baseline)...HEAD"],
                in: repository,
                allowsOptionalLocks: false
            ),
            // 基线不存在、或者两边根本没有共同祖先时 git 直接报错退出
            // （实测 `fatal: no merge base`），此时给不出结论，就别硬给
            result.isSuccess
        else { return [] }

        return Set(
            NameStatusParser.parse(result.standardOutput)
                .flatMap { [$0.path, $0.sourcePath].compactMap { $0 } })
    }

    /// 这个 worktree 自己那几条提交里，最近一条带会话记录的。
    private func latestSession(
        in repository: URL,
        since baseline: String,
        among sessions: [String: AISession]
    ) async -> AISession? {
        guard !sessions.isEmpty else { return nil }

        // 两点而不是三点：这里要的是「我这边的提交」这个列表本身。
        // 两点在两边毫无共同祖先时也照样能用（三点会 fatal）。
        guard
            let result = try? await runReturningResult(
                ["rev-list", "--max-count=100", "\(baseline)..HEAD"],
                in: repository,
                allowsOptionalLocks: false
            ),
            result.isSuccess
        else { return nil }

        // rev-list 默认从新到旧，第一个命中的就是最近的那次
        for line in result.standardOutputText.split(separator: "\n") {
            if let session = sessions[String(line)] { return session }
        }
        return nil
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
