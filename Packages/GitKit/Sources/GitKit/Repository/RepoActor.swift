import Foundation

/// 单个仓库的操作入口。
///
/// 用 `actor` 而不是普通类型，是为了**串行化写操作**：GUI 上快速连点两次「暂存」会并发
/// 发出两条 git 命令，而 git 用 `index.lock` 独占 index，后到的那条会直接失败。
/// actor 保证同一时刻只有一个写操作在跑。
///
/// 只读查询标记为 `nonisolated`，不占用这条串行队列——否则一次 5 万 commit 的历史加载
/// 会把所有交互堵死。
///
/// - Important: 仓库的写操作只能经由 ``perform(_:)``。绕过它直接调 ``GitClient`` 执行写
///   命令，等于在时间线上凿一个洞——那次改动将无法被撤销，也不会出现在时间线里。
public actor RepoActor {

    /// 仓库根目录。不可变的身份标识，标记 `nonisolated` 让外部无需 await 即可读取
    /// （跨模块访问 actor 的 `let` 属性默认仍是隔离的）。
    public nonisolated let root: URL

    public nonisolated let client: GitClient

    private let timeline: Timeline

    /// 写操作串行队列的队尾。
    ///
    /// **光靠 actor 隔离串行化不了写操作**：actor 是可重入的——方法在 `await` 处挂起时
    /// 会释放执行权，另一个任务立刻能进来跑到它自己的 `await`。于是两条 `git add` 真的
    /// 会同时在跑，撞上 `index.lock`（退出码 128）。这里把每个操作显式排在前一个之后，
    /// 靠 Task 链拿到真正的互斥。
    private var queueTail: Task<Void, Never>?

    public init(root: URL, client: GitClient, timeline: Timeline) {
        self.root = root
        self.client = client
        self.timeline = timeline
    }

    /// 便于测试与预览：用内存日志加真实快照存储组一条时间线。
    public init(root: URL, client: GitClient, operationLog: OperationLogging) async throws {
        let snapshots = try await SnapshotStore.open(root: root, client: client)
        self.init(root: root, client: client, timeline: Timeline(log: operationLog, snapshots: snapshots))
    }

    /// 打开指定路径所在的仓库，日志落在仓库自己的 git 目录里。
    public static func open(at path: URL, client: GitClient? = nil) async throws -> RepoActor {
        let client = try client ?? GitClient()
        let root = try await client.repositoryRoot(containing: path)
        let timeline = try await Timeline.open(root: root, client: client)
        return RepoActor(root: root, client: client, timeline: timeline)
    }

    // MARK: - 写

    /// 执行一个写操作并记入操作日志。**这是仓库唯一的写入口。**
    ///
    /// 无论成功还是失败都会留下记录：失败的尝试同样是用户想在时间线上看到的东西
    /// （「我刚才那步为什么没生效」）。
    /// - Parameter standardInput: 需要经 stdin 交给 git 的数据，目前只有 patch 用到。
    ///   它**不会**进入操作日志——patch 内容就是用户的代码，工程规范 §7 要求日志不含文件内容。
    @discardableResult
    public func perform(
        _ operation: GitOperation,
        standardInput: Data? = nil
    ) async throws -> ProcessResult {
        // 从读取队尾到更新队尾之间没有 await，这一段是 actor 的同步区，
        // 不会有第二个任务插进来，排队顺序因此是确定的。
        let previous = queueTail

        let work = Task { [self] in
            await previous?.value
            return try await execute(operation, standardInput: standardInput)
        }
        queueTail = Task { _ = try? await work.value }

        return try await work.value
    }

    private func execute(_ operation: GitOperation, standardInput: Data?) async throws -> ProcessResult {
        try await recording(operation) { [self] in
            try await client.run(operation.arguments, in: root, standardInput: standardInput)
        }
    }

    /// 执行一次 interactive rebase 并记入时间线。
    ///
    /// 不走 ``perform(_:standardInput:)`` 是因为 rebase 不是一条 git 命令：它要先写
    /// todo 文件、设环境变量，中途还可能停在冲突上。但**时间线该记的一样不少**——
    /// 同样排在写队列里、同样先拍快照、同样留下记录。架构铁律 1 要的是
    /// 「每个写操作可记录可逆推」，而不是「每个写操作只能有一条 git 命令」。
    ///
    /// 另外单独打一个备份 tag：快照保的是工作区，而 rebase 改的是历史，
    /// 要退回去得有个指向原 HEAD 的引用。
    /// - Returns: rebase 结果和备份 tag 名。
    public func performRebase(
        _ todo: RebaseTodo,
        summary: String
    ) async throws -> (outcome: RebaseOutcome, backupTag: String?) {
        let previous = queueTail

        let work = Task { [self] in
            await previous?.value

            let backupTag = try? await client.createBackupTag(in: root, label: summary)

            let operation = GitOperation.interactiveRebase(
                base: todo.base,
                summary: summary,
                backupTag: backupTag
            )

            let outcome = try await recording(operation, resultOf: { $0 == .completed }) {
                [self] in
                try await client.performInteractiveRebase(todo, in: root)
            }
            return (outcome, backupTag)
        }
        queueTail = Task { _ = try? await work.value }

        return try await work.value
    }

    /// 跑一段写操作，前后该拍的快照、该记的日志都补上。
    ///
    /// - Parameter isSuccess: 从返回值判断这次算不算成功。git 命令看抛不抛错就够了，
    ///   但 rebase 会「正常返回一个冲突结果」，那在时间线上应当记成失败。
    private func recording<Result>(
        _ operation: GitOperation,
        resultOf isSuccess: (Result) -> Bool = { _ in true },
        work: () async throws -> Result
    ) async throws -> Result {
        let headBefore = await currentHead()
        // 危险操作先留退路。安全操作不拍——拍快照要遍历工作区，高频操作上会明显拖慢。
        let snapshot = await timeline.snapshotIfNeeded(before: operation)

        do {
            let result = try await work()
            await log(
                operation,
                headBefore: headBefore,
                headAfter: await currentHead(),
                outcome: isSuccess(result)
                    ? .succeeded
                    : .failed(exitCode: 1, message: "操作未能完成"),
                snapshot: snapshot
            )
            return result
        } catch {
            let outcome = OperationRecord.Outcome.failed(
                exitCode: (error as? GitError).flatMap(Self.exitCode) ?? -1,
                message: String(describing: error)
            )
            await log(
                operation,
                headBefore: headBefore,
                headAfter: headBefore,
                outcome: outcome,
                snapshot: snapshot
            )
            throw error
        }
    }

    // MARK: - 读

    /// 读取仓库当前状态。不占用写队列，可与写操作并发。
    public nonisolated func status(
        untrackedFiles: GitClient.UntrackedFilesMode = .all,
        includeIgnored: Bool = false
    ) async throws -> RepositoryStatus {
        try await client.status(
            of: root,
            untrackedFiles: untrackedFiles,
            includeIgnored: includeIgnored
        )
    }

    /// 时间线条目，按时间正序。
    public func timelineEntries(limit: Int = 100) async throws -> [TimelineEntry] {
        try await timeline.entries(limit: limit)
    }

    /// 撤销某一项操作，退回它执行之前的工作区状态。
    public func undo(_ entry: TimelineEntry) async throws {
        try await timeline.undo(entry)
    }

    /// 为外部改动打一个时间点。
    @discardableResult
    public func captureExternalChange(summary: String) async -> Snapshot? {
        await timeline.captureExternalChange(summary: summary)
    }

    /// 全部快照，按时间倒序。
    public func timelineSnapshots() async throws -> [Snapshot] {
        try await timeline.allSnapshots()
    }

    /// 直接恢复到某张快照。
    public func restoreSnapshot(_ snapshot: Snapshot) async throws {
        try await timeline.restore(snapshot)
    }

    // MARK: - 内部

    /// 日志写入失败不能阻断用户的操作，但会让时间线缺一段。
    /// v0.5 时间线正式化时需要重新审视这里的取舍（例如危险操作在日志不可用时拒绝执行）。
    private func log(
        _ operation: GitOperation,
        headBefore: String?,
        headAfter: String?,
        outcome: OperationRecord.Outcome,
        snapshot: Snapshot?
    ) async {
        let record = OperationRecord(
            operation: operation,
            headBefore: headBefore,
            headAfter: headAfter,
            outcome: outcome,
            snapshotReference: snapshot?.reference
        )
        await timeline.record(record)
    }

    /// 当前 HEAD 指向的 commit；仓库尚无提交（unborn）时为 nil。
    private func currentHead() async -> String? {
        guard
            let result = try? await client.runReturningResult(["rev-parse", "HEAD"], in: root),
            result.isSuccess
        else {
            return nil
        }
        return result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func exitCode(of error: GitError) -> Int32? {
        if case let .commandFailed(_, exitCode, _) = error { exitCode } else { nil }
    }
}
