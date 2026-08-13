import Foundation
import GitKit
import Observation

/// 单个仓库窗口的状态。
///
/// 只做「取数据 → 交给视图」与「把用户意图转成 GitOperation」，不含 git 逻辑——
/// 那些都在 GitKit 里，这样 git 的边缘 case 能用不带 UI 的测试覆盖。
@Observable
@MainActor
final class RepositoryViewModel {

    /// 变更列表中被选中的文件。同一个文件可能同时出现在已暂存与未暂存两侧，
    /// 要连着暂存状态一起记，否则会取错 diff。
    struct FileSelection: Hashable {
        let path: String
        let isStaged: Bool
    }

    let root: URL
    var displayName: String { root.lastPathComponent }

    private(set) var status: RepositoryStatus?
    private(set) var branches: [Branch] = []
    private(set) var tags: [Tag] = []
    private(set) var commits: [Commit] = []

    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    var selectedCommit: Commit.ID?
    var selectedFile: FileSelection?

    /// 当前选中文件的 diff。
    private(set) var selectedDiff: FileDiff?
    private(set) var isLoadingDiff = false

    /// 提交框里的内容。
    var commitMessage = ""
    var isAmending = false

    private let repo: RepoActor
    private var watcher: RepositoryWatcher?

    /// 首屏加载的提交数。PRD 要求 5 万 commit 仓库首屏 500ms 内出来，
    /// 先取够填满一屏的量，滚动时再增量加载（v0.3 做）。
    private let initialCommitCount = 200

    init(url: URL) async throws {
        repo = try await RepoActor.open(at: url)
        root = repo.root
    }

    // MARK: - 生命周期

    /// 开始监听外部改动。PRD 要求终端、编辑器、agent 的改动 500ms 内反映到界面。
    func startWatching() {
        guard watcher == nil else { return }
        let watcher = RepositoryWatcher(root: root) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
        watcher.start()
        self.watcher = watcher
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: - 读取

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // 四个查询互不依赖，并发发出去；它们都是只读的，不占写队列
            async let statusResult = repo.status()
            async let branchResult = repo.client.branches(in: repo.root)
            async let tagResult = repo.client.tags(in: repo.root)
            async let commitResult = repo.client.log(
                in: repo.root,
                includingAllRefs: true,
                maxCount: initialCommitCount
            )

            status = try await statusResult
            branches = try await branchResult
            tags = try await tagResult
            commits = try await commitResult
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }

        await reloadSelectedDiff()
    }

    /// 加载当前选中文件的 diff。
    func reloadSelectedDiff() async {
        guard let selection = selectedFile else {
            selectedDiff = nil
            return
        }

        isLoadingDiff = true
        defer { isLoadingDiff = false }

        do {
            let entry = status?.entries.first { $0.path == selection.path }
            if entry?.kind == .untracked {
                // 未跟踪文件在 git diff 里看不到，得跟 /dev/null 比
                selectedDiff = try await repo.client.diffForUntrackedFile(
                    at: selection.path, in: root)
            } else {
                selectedDiff = try await repo.client.diff(
                    of: selection.path, in: root, staged: selection.isStaged)
            }
        } catch {
            selectedDiff = nil
            errorMessage = "\(error)"
        }
    }

    // MARK: - 暂存

    func stage(_ paths: [String]) async {
        await mutate { try await self.repo.perform(.stage(paths: paths)) }
    }

    func unstage(_ paths: [String]) async {
        await mutate { try await self.repo.perform(.unstage(paths: paths)) }
    }

    func stageHunk(at index: Int, in path: String) async {
        await mutate { _ = try await self.repo.stagePartial(path: path, selecting: .hunks([index])) }
    }

    func unstageHunk(at index: Int, in path: String) async {
        await mutate { _ = try await self.repo.unstagePartial(path: path, selecting: .hunks([index])) }
    }

    func stageLines(_ lines: Set<Int>, inHunk hunkIndex: Int, of path: String) async {
        await mutate {
            _ = try await self.repo.stagePartial(path: path, selecting: .lines([hunkIndex: lines]))
        }
    }

    func discard(_ paths: [String]) async {
        // 调用方负责先向用户确认：这些改动没进过 git 对象库，
        // 在时间线快照落地（v0.5）之前丢了就真没了。
        await mutate { try await self.repo.perform(.discard(paths: paths)) }
    }

    // MARK: - 提交

    var canCommit: Bool {
        !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!stagedEntries.isEmpty || isAmending)
    }

    func commit() async {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        let amend = isAmending
        await mutate { try await self.repo.perform(.commit(message: message, amend: amend)) }

        if errorMessage == nil {
            commitMessage = ""
            isAmending = false
        }
    }

    /// 载入上一条提交的信息，供 amend 编辑。
    func prepareAmend() async {
        guard let head = commits.first else { return }
        commitMessage = head.message
        isAmending = true
    }

    // MARK: - 内部

    /// 执行写操作：挂起监听避免自己刷自己，完成后主动刷新。
    ///
    /// 这里手动 suspend/resume 而不用 `whileSuspended`：闭包是 MainActor 隔离的，
    /// 交给非隔离的 watcher 去调用会跨越隔离边界，Swift 6 会判定有数据竞争风险。
    private func mutate(_ work: () async throws -> Void) async {
        watcher?.suspend()
        do {
            try await work()
            errorMessage = nil
        } catch {
            errorMessage = "\(error)"
        }
        watcher?.resume()

        await refresh()
    }

    // MARK: - 派生数据

    var currentBranch: Branch? {
        branches.first { $0.isCurrent }
    }

    var localBranches: [Branch] {
        branches.filter { !$0.isRemote }.sorted { $0.name < $1.name }
    }

    var remoteBranches: [Branch] {
        branches.filter(\.isRemote).sorted { $0.name < $1.name }
    }

    var stagedEntries: [StatusEntry] {
        status?.entries.filter(\.hasStagedChanges) ?? []
    }

    var unstagedEntries: [StatusEntry] {
        status?.entries.filter { $0.hasUnstagedChanges || $0.kind == .untracked } ?? []
    }

    var conflictedEntries: [StatusEntry] {
        status?.entries.filter { $0.kind == .unmerged } ?? []
    }

    var hasChanges: Bool {
        !stagedEntries.isEmpty || !unstagedEntries.isEmpty
    }
}
