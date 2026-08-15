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
    private(set) var remotes: [Remote] = []

    /// 提交历史的分支图布局。
    private(set) var graph = CommitGraph(commits: [])
    /// 还有更早的提交没加载。
    private(set) var hasMoreCommits = true
    private var isLoadingMoreCommits = false

    private(set) var isRefreshing = false

    /// 需要弹给用户的失败信息，含中文说明与下一步建议。
    var failure: FailurePresentation?

    /// 正在进行的网络传输进度。
    private(set) var transferProgress: TransferProgress?
    private(set) var isTransferring = false

    var selectedCommit: Commit.ID? {
        didSet {
            guard selectedCommit != oldValue else { return }
            // 换了提交，之前点开的那个文件和它的 diff 都不再相干。
            //
            // 清空放在这里而不是 reloadSelectedCommitFiles() 里：那是个「加载数据」
            // 的方法，把「重置选中」这种副作用塞进去，任何一次意外的重复调用都会
            // 把用户刚点开的文件清掉。事实上就发生过——视图重建让 .task 重新触发，
            // 表现成「点文件毫无反应」，实际是点开又瞬间关上了。
            // 状态归零属于「选中变了」这个事件，就该挂在选中上。
            selectedCommitFile = nil
            commitFileDiff = nil
        }
    }
    var selectedFile: FileSelection?

    /// 历史过滤条件。**交给 git 去筛，不在已加载的那几百条里过滤**——
    /// 客户端过滤搜不到时用户会以为"仓库里没有"，而它可能在第 300 条。
    var historyFilter = HistoryFilter() {
        didSet {
            guard historyFilter != oldValue else { return }
            scheduleHistoryReload()
        }
    }
    private(set) var isFilteringHistory = false
    private var historyReloadTask: Task<Void, Never>?

    /// 当前选中文件的 diff。
    private(set) var selectedDiff: FileDiff?
    private(set) var isLoadingDiff = false

    /// 当前选中提交改动了哪些文件。
    private(set) var selectedCommitFiles: [CommitFileChange] = []
    private(set) var isLoadingCommitFiles = false

    /// 在提交详情里点开的那个文件，以及它在这次提交中的 diff。
    var selectedCommitFile: CommitFileChange?
    private(set) var commitFileDiff: FileDiff?
    private(set) var isLoadingCommitFileDiff = false

    /// 提交框里的内容。
    var commitMessage = ""
    var isAmending = false

    /// AI 起草提交信息的状态。见 `RepositoryViewModel+AI.swift`。
    var aiState = AIGenerationState()

    /// 正卡在一次 rebase 中间时的进度，没有则为 nil。见 `RepositoryViewModel+Rebase.swift`。
    var rebaseProgress: RebaseProgress?
    /// 最近一次改写历史前打的备份 tag，界面上据此提示「可以退回去」。
    var lastBackupTag: String?

    /// 时间线条目与可恢复的时间点。
    var timelineEntries: [TimelineEntry] = []
    var timelineSnapshots: [Snapshot] = []

    /// 上次为外部改动打点的时刻，用于限流。
    var lastExternalCapture: Date?
    /// 两次外部打点之间的最小间隔。编辑器每次保存都拍会让仓库迅速膨胀。
    static let externalCaptureInterval: TimeInterval = 30

    let repository: RepoActor
    private var watcher: RepositoryWatcher?

    /// 全仓库即时搜索。
    ///
    /// 在 init 里建好而不是延迟创建：@Observable 宏会把存储属性改写成计算属性，
    /// 与 lazy 不兼容。
    let search: SearchModel

    /// 首屏加载的提交数。PRD 要求 5 万 commit 仓库首屏 500ms 内出来，
    /// 先取够填满一屏的量，滚动时再增量加载（v0.3 做）。
    private let initialCommitCount = 200
    /// 每次增量加载的条数。
    private let pageSize = 500

    init(url: URL) async throws {
        repository = try await RepoActor.open(at: url)
        root = repository.root
        search = SearchModel(client: repository.client, root: repository.root)
    }

    // MARK: - 生命周期

    /// 后台准备 commit-graph 缓存。
    ///
    /// 分支图必须用拓扑序才不会画错，而拓扑序要求 git 遍历完整提交图——
    /// 5 万 commit 上取首屏要 370ms，有缓存则降到 40ms。放在后台做，
    /// 首屏不等它，写完之后的每次刷新都会受益。
    func prepareCommitGraphCache() {
        Task.detached(priority: .background) { [client = repository.client, root] in
            guard await !client.hasCommitGraph(in: root) else { return }
            try? await client.writeCommitGraph(in: root)
        }
    }

    /// 开始监听外部改动。PRD 要求终端、编辑器、agent 的改动 500ms 内反映到界面。
    func startWatching() {
        guard watcher == nil else { return }
        let watcher = RepositoryWatcher(root: root) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                await self.refresh()
                // 外部改动同样要留退路，这是 Claude Code 的 checkpoint 管不到的部分
                await self.captureExternalChangeIfNeeded()
            }
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
            async let statusResult = repository.status()
            async let branchResult = repository.client.branches(in: repository.root)
            async let tagResult = repository.client.tags(in: repository.root)
            // remote 列表用来拼提交信息里的 issue 链接。跟着 refresh 一起取，
            // 这样在远程管理面板里改完之后立刻生效（`mutate` 结束会调 refresh）
            async let remoteResult = repository.client.remotes(in: repository.root)
            // 带上过滤条件：外部改动触发的自动刷新如果不带，
            // 用户正在看的筛选结果会被无声地冲回全量列表
            async let commitResult = repository.client.log(
                in: repository.root,
                includingAllRefs: true,
                // 画分支图必须用拓扑序，按时间排会让线出现视觉上的交叉错乱
                order: .topological,
                maxCount: initialCommitCount,
                filter: historyFilter
            )

            status = try await statusResult
            branches = try await branchResult
            tags = try await tagResult
            remotes = (try? await remoteResult) ?? []
            commits = try await commitResult
            graph = CommitGraph(commits: commits)
            hasMoreCommits = commits.count >= initialCommitCount
            failure = nil
        } catch {
            failure = FailurePresentation(from: error)
        }

        await reloadSelectedDiff()
    }

    /// 过滤条件变了，稍后重新查历史。
    ///
    /// 防抖 250ms：每按一个键就跑一次 git log，在大仓库上会把 CPU 打满，
    /// 而且前面几次的结果都还没画出来就作废了。
    private func scheduleHistoryReload() {
        historyReloadTask?.cancel()
        historyReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.reloadHistory()
        }
    }

    /// 按当前过滤条件重新查历史。
    func reloadHistory() async {
        isFilteringHistory = !historyFilter.isEmpty
        do {
            let found = try await repository.client.log(
                in: root,
                includingAllRefs: true,
                order: .topological,
                maxCount: initialCommitCount,
                filter: historyFilter
            )
            commits = found
            graph = CommitGraph(commits: found)
            hasMoreCommits = found.count >= initialCommitCount
            // 筛完之后原来选中的提交可能已经不在列表里了
            if let selected = selectedCommit, !found.contains(where: { $0.id == selected }) {
                selectedCommit = nil
            }
        } catch {
            guard !error.isCancellation else { return }
            failure = FailurePresentation(from: error)
        }
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
                selectedDiff = try await repository.client.diffForUntrackedFile(
                    at: selection.path, in: root)
            } else {
                selectedDiff = try await repository.client.diff(
                    of: selection.path, in: root, staged: selection.isStaged)
            }
        } catch {
            guard !error.isCancellation else { return }
            selectedDiff = nil
            failure = FailurePresentation(from: error)
        }
    }

    /// 加载当前选中提交改动了哪些文件。
    ///
    /// 单独一个方法而不是并进 `reloadSelectedDiff`：选中提交和选中文件是
    /// 两条互斥的路径（选了提交就不会有选中文件），混在一起只会让两边都多一层判断。
    func reloadSelectedCommitFiles() async {
        // 这里**只加载，不重置选中**——重置由 selectedCommit 的 didSet 负责。
        // 见那里的注释：把副作用塞进加载方法会让重复调用清掉用户的选择。
        guard let id = selectedCommit,
            let commit = commits.first(where: { $0.id == id })
        else {
            selectedCommitFiles = []
            return
        }

        isLoadingCommitFiles = true
        defer { isLoadingCommitFiles = false }

        do {
            selectedCommitFiles = try await repository.client.filesChanged(
                inCommit: commit.hash, in: root)
        } catch {
            // 取消时保留旧列表，等新一轮填上，免得切提交时闪一下空白
            guard !error.isCancellation else { return }
            // 列不出文件不该弹错误打断人——提交信息本身还是有用的，
            // 静默留空即可，界面上会显示「列不出改动的文件」。
            selectedCommitFiles = []
        }
    }

    /// 加载提交详情里点开的那个文件的 diff。
    func reloadCommitFileDiff() async {
        guard let change = selectedCommitFile,
            let id = selectedCommit,
            let commit = commits.first(where: { $0.id == id })
        else {
            commitFileDiff = nil
            return
        }

        isLoadingCommitFileDiff = true
        defer { isLoadingCommitFileDiff = false }

        do {
            commitFileDiff = try await repository.client.diff(
                ofFile: change, inCommit: commit.hash, in: root)
        } catch {
            // 被取消说明用户已经点了别的，新一轮请求正在路上。
            // 此时清空会让 diff 区先闪一下白再填上新内容——连点几下就是一串闪烁。
            // 保留旧内容直到新的到达，视觉上是连续的。
            guard !error.isCancellation else { return }
            commitFileDiff = nil
            failure = FailurePresentation(from: error)
        }
    }

    // MARK: - 暂存

    func stage(_ paths: [String]) async {
        await mutate { try await self.repository.perform(.stage(paths: paths)) }
    }

    func unstage(_ paths: [String]) async {
        await mutate { try await self.repository.perform(.unstage(paths: paths)) }
    }

    func stageHunk(at index: Int, in path: String) async {
        await mutate { _ = try await self.repository.stagePartial(path: path, selecting: .hunks([index])) }
    }

    func unstageHunk(at index: Int, in path: String) async {
        await mutate { _ = try await self.repository.unstagePartial(path: path, selecting: .hunks([index])) }
    }

    /// 暂存或取消暂存选中的行。
    ///
    /// - Parameter lines: 键是 hunk 下标，值是该 hunk 内选中的行下标。
    func applyLines(_ lines: [Int: Set<Int>], of path: String, isStaged: Bool) async {
        guard !lines.isEmpty else { return }
        await mutate {
            if isStaged {
                _ = try await self.repository.unstagePartial(path: path, selecting: .lines(lines))
            } else {
                _ = try await self.repository.stagePartial(path: path, selecting: .lines(lines))
            }
        }
    }

    func discard(_ paths: [String]) async {
        // 调用方负责先向用户确认：这些改动没进过 git 对象库，
        // 在时间线快照落地（v0.5）之前丢了就真没了。
        await mutate { try await self.repository.perform(.discard(paths: paths)) }
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
        await mutate { try await self.repository.perform(.commit(message: message, amend: amend)) }

        if failure == nil {
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
    /// - Returns: 闭包的返回值；失败时为 nil。多数写操作没有返回值，
    ///   但 cherry-pick 与 revert 要把「完成了还是停在冲突上」带回给界面。
    @discardableResult
    func mutate<Value>(_ work: () async throws -> Value) async -> Value? {
        watcher?.suspend()
        var value: Value?
        do {
            value = try await work()
            failure = nil
        } catch {
            failure = FailurePresentation(from: error)
        }
        watcher?.resume()

        await refresh()
        return value
    }

    /// 执行网络操作：进度实时更新，失败转成带建议的中文提示。
    func transfer(
        _ work: (GitClient, URL, @escaping @Sendable (TransferProgress) -> Void) async throws -> Void
    ) async {
        guard !isTransferring else { return }
        isTransferring = true
        transferProgress = nil
        watcher?.suspend()

        do {
            try await work(repository.client, root) { progress in
                // 回调来自读取 stderr 的后台线程
                Task { @MainActor in self.transferProgress = progress }
            }
            failure = nil
        } catch {
            failure = FailurePresentation(from: error)
        }

        watcher?.resume()
        isTransferring = false
        transferProgress = nil
        await refresh()
    }

    /// 滚动接近底部时加载更早的提交。
    func loadMoreCommits() async {
        guard hasMoreCommits, !isLoadingMoreCommits, !commits.isEmpty else { return }
        isLoadingMoreCommits = true
        defer { isLoadingMoreCommits = false }

        do {
            let more = try await repository.client.log(
                in: root,
                includingAllRefs: true,
                order: .topological,
                maxCount: pageSize,
                skip: commits.count
            )
            guard !more.isEmpty else {
                hasMoreCommits = false
                return
            }

            commits += more
            // 图必须整体重算：新加载的提交可能是前面某条分支线的父，
            // 只算增量会漏掉那些跨页的连线
            graph = CommitGraph(commits: commits)
            hasMoreCommits = more.count >= pageSize
        } catch {
            hasMoreCommits = false
        }
    }

    /// 从搜索结果跳到某个文件：选中它并切到变更列表。
    func reveal(path: String) {
        let staged = stagedEntries.contains { $0.path == path }
        selectedFile = FileSelection(path: path, isStaged: staged)
        selectedCommit = nil
    }

    /// 从搜索结果跳到某条提交。
    func reveal(commit: Commit) {
        selectedCommit = commit.id
        selectedFile = nil
        // 搜索能跨分支找到提交，它未必在当前加载的首屏里
        if !commits.contains(where: { $0.id == commit.id }) {
            commits.insert(commit, at: 0)
        }
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
