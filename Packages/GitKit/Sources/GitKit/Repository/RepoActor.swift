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

    private let operationLog: OperationLogging

    /// 写操作串行队列的队尾。
    ///
    /// **光靠 actor 隔离串行化不了写操作**：actor 是可重入的——方法在 `await` 处挂起时
    /// 会释放执行权，另一个任务立刻能进来跑到它自己的 `await`。于是两条 `git add` 真的
    /// 会同时在跑，撞上 `index.lock`（退出码 128）。这里把每个操作显式排在前一个之后，
    /// 靠 Task 链拿到真正的互斥。
    private var queueTail: Task<Void, Never>?

    public init(root: URL, client: GitClient, operationLog: OperationLogging) {
        self.root = root
        self.client = client
        self.operationLog = operationLog
    }

    /// 打开指定路径所在的仓库，日志落在仓库自己的 git 目录里。
    public static func open(at path: URL, client: GitClient? = nil) async throws -> RepoActor {
        let client = try client ?? GitClient()
        let root = try await client.repositoryRoot(containing: path)
        let log = try await FileOperationLog(repository: root, client: client)
        return RepoActor(root: root, client: client, operationLog: log)
    }

    // MARK: - 写

    /// 执行一个写操作并记入操作日志。**这是仓库唯一的写入口。**
    ///
    /// 无论成功还是失败都会留下记录：失败的尝试同样是用户想在时间线上看到的东西
    /// （「我刚才那步为什么没生效」）。
    @discardableResult
    public func perform(_ operation: GitOperation) async throws -> ProcessResult {
        // 从读取队尾到更新队尾之间没有 await，这一段是 actor 的同步区，
        // 不会有第二个任务插进来，排队顺序因此是确定的。
        let previous = queueTail

        let work = Task { [self] in
            await previous?.value
            return try await execute(operation)
        }
        queueTail = Task { _ = try? await work.value }

        return try await work.value
    }

    private func execute(_ operation: GitOperation) async throws -> ProcessResult {
        let headBefore = await currentHead()

        do {
            let result = try await client.run(operation.arguments, in: root)
            await log(operation, headBefore: headBefore, headAfter: await currentHead(), outcome: .succeeded)
            return result
        } catch {
            let outcome = OperationRecord.Outcome.failed(
                exitCode: (error as? GitError).flatMap(Self.exitCode) ?? -1,
                message: String(describing: error)
            )
            await log(operation, headBefore: headBefore, headAfter: headBefore, outcome: outcome)
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

    /// 最近的操作记录，按时间正序。
    public func operationHistory(limit: Int = 100) async throws -> [OperationRecord] {
        try await operationLog.recent(limit: limit)
    }

    // MARK: - 内部

    /// 日志写入失败不能阻断用户的操作，但会让时间线缺一段。
    /// v0.5 时间线正式化时需要重新审视这里的取舍（例如危险操作在日志不可用时拒绝执行）。
    private func log(
        _ operation: GitOperation,
        headBefore: String?,
        headAfter: String?,
        outcome: OperationRecord.Outcome
    ) async {
        let record = OperationRecord(
            operation: operation,
            headBefore: headBefore,
            headAfter: headAfter,
            outcome: outcome
        )
        try? await operationLog.record(record)
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
