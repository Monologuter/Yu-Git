import Foundation

/// 两个以上 worktree 都碰过同一个文件。
///
/// 这是并行 agent 最典型的翻车方式：两个 agent 各自在自己的 worktree 里
/// 改同一个文件，各自都很顺利，合的时候才发现要手工解冲突——而那时两边
/// 都已经改出去很远了。**趁早说**比事后解便宜得多。
public struct WorktreeOverlap: Sendable, Equatable, Identifiable {

    public var id: String { path }

    public let path: String
    /// 碰过它的 worktree 路径，顺序跟 ``WorktreeOverview/statuses`` 一致。
    public let worktreePaths: [String]

    public init(path: String, worktreePaths: [String]) {
        self.path = path
        self.worktreePaths = worktreePaths
    }
}

/// 跨 worktree 的改动汇总，一屏看全。
public struct WorktreeOverview: Sendable, Equatable {

    public let statuses: [WorktreeStatus]
    /// worktree 路径 → 它碰过的文件。
    ///
    /// **未提交的和已提交的都算。** 只看未提交的会漏掉「A 已经提交了对 F 的改动、
    /// B 正在改 F」这种情形，而那同样会在合并时撞上。
    public let touchedPaths: [String: Set<String>]
    /// 撞在一起的文件，按涉及的 worktree 数从多到少。
    public let overlaps: [WorktreeOverlap]

    public init(statuses: [WorktreeStatus], touchedPaths: [String: Set<String>]) {
        self.statuses = statuses
        self.touchedPaths = touchedPaths
        self.overlaps = Self.findOverlaps(
            in: touchedPaths,
            order: statuses.map(\.worktree.path)
        )
    }

    /// 找出被多个 worktree 碰过的文件。
    ///
    /// 顺序按 `order` 给的来，而不是字典的遍历顺序——字典无序，
    /// 不固定住的话同样的仓库每次刷新出来的排列都不一样。
    static func findOverlaps(
        in touchedPaths: [String: Set<String>],
        order: [String]
    ) -> [WorktreeOverlap] {
        var owners: [String: [String]] = [:]
        for worktree in order {
            for path in (touchedPaths[worktree] ?? []).sorted() {
                owners[path, default: []].append(worktree)
            }
        }

        return
            owners
            .filter { $0.value.count > 1 }
            .map { WorktreeOverlap(path: $0.key, worktreePaths: $0.value) }
            // 撞的人越多越该先看；同样多时按路径排，免得每次刷新顺序都在跳
            .sorted { ($1.worktreePaths.count, $0.path) < ($0.worktreePaths.count, $1.path) }
    }
}
