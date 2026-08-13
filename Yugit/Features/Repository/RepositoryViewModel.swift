import Foundation
import GitKit
import Observation

/// 单个仓库窗口的状态。
///
/// 只做「取数据 → 交给视图」，不含 git 逻辑——那些都在 GitKit 里，
/// 这样 git 的边缘 case 能用不带 UI 的测试覆盖。
@Observable
@MainActor
final class RepositoryViewModel {

    let root: URL
    var displayName: String { root.lastPathComponent }

    private(set) var status: RepositoryStatus?
    private(set) var branches: [Branch] = []
    private(set) var tags: [Tag] = []
    private(set) var commits: [Commit] = []

    private(set) var isRefreshing = false
    private(set) var errorMessage: String?

    /// 侧栏与列表的选中项。
    var selectedCommit: Commit.ID?
    var selectedFile: String?

    private let repo: RepoActor

    /// 首屏加载的提交数。PRD 要求 5 万 commit 仓库首屏 500ms 内出来，
    /// 先取够填满一屏的量，滚动时再增量加载（v0.3 做）。
    private let initialCommitCount = 200

    init(url: URL) async throws {
        repo = try await RepoActor.open(at: url)
        root = repo.root
    }

    // MARK: - 数据

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            // 三个查询互不依赖，并发发出去；它们都是只读的，不占写队列
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
