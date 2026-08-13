import Foundation

/// 提交历史的排序方式。
///
/// 三者在大仓库上的代价差一个数量级，5 万 commit 基准仓库取首屏 200 条的实测：
///
/// | 排序 | 耗时 | 有 commit-graph |
/// |---|---|---|
/// | ``chronological`` | 20ms | 20ms |
/// | ``date`` | 350ms | 40ms |
/// | ``topological`` | 350ms | 40ms |
public enum CommitOrder: Sendable {

    /// git 的默认排序：纯按提交时间倒序，用优先队列边遍历边输出。
    ///
    /// **首屏默认用这个**——取 200 条就只做 200 条的工作。代价是父提交可能排在子提交
    /// 之前（当系统时钟回拨或 rebase 改写时间时），画分支图会错乱，但纯列表阅读无碍。
    case chronological

    /// 时间序，外加「父提交不早于子提交」的约束。
    ///
    /// 名字听着像只是排序，实则和 ``topological`` 一样要遍历**完整**提交图才能确定顺序，
    /// 哪怕只取 200 条——代价与拓扑序相同，不要因为名字无害就随手用。
    case date

    /// 拓扑序：父提交永远排在子提交之后，分支图渲染需要它才不会出现视觉上的交叉错乱。
    ///
    /// 同样需要遍历完整提交图。v0.3 上分支图时应配套维护 commit-graph 缓存，
    /// 能把这个代价压回 40ms。
    case topological

    var argument: String? {
        switch self {
        case .chronological: nil
        case .date: "--date-order"
        case .topological: "--topo-order"
        }
    }
}

extension GitClient {

    /// 读取提交历史。
    ///
    /// - Parameters:
    ///   - includingAllRefs: 为 `true` 时列出所有引用可达的提交（`--all`），
    ///     而不只是当前 HEAD 这条线——GUI 的分支图需要看到全部分支。
    ///   - order: 默认按时间排序。只有要画分支图时才值得付拓扑排序的代价，
    ///     见 ``CommitOrder/topological``。
    ///   - maxCount / skip: 分页。5 万 commit 的仓库不能一次全读进来。
    public func log(
        in repository: URL,
        includingAllRefs: Bool = false,
        order: CommitOrder = .chronological,
        maxCount: Int? = nil,
        skip: Int? = nil,
        paths: [String] = []
    ) async throws -> [Commit] {
        var arguments = [
            "log",
            "--format=\(LogParser.format)",
            // 输出 refs/heads/main 这样的完整路径；短名无法区分同名的分支与 tag
            "--decorate=full",
        ]
        if let orderArgument = order.argument {
            arguments.append(orderArgument)
        }
        if includingAllRefs {
            arguments.append("--all")
        }
        if let maxCount {
            arguments.append("--max-count=\(maxCount)")
        }
        if let skip {
            arguments.append("--skip=\(skip)")
        }
        if !paths.isEmpty {
            arguments.append("--")
            arguments += paths
        }

        let result = try await runReturningResult(arguments, in: repository, allowsOptionalLocks: false)

        if !result.isSuccess {
            // 还没有任何提交的仓库上 git log 会失败。这不是错误，是空历史。
            if result.standardErrorText.contains("does not have any commits yet")
                || result.standardErrorText.contains("bad default revision")
            {
                return []
            }
            throw GitError.commandFailed(
                arguments: arguments,
                exitCode: result.exitCode,
                standardError: result.standardErrorText
            )
        }

        return try LogParser.parse(result.standardOutput)
    }

    /// 统计提交总数，用于分页与进度显示。
    public func commitCount(in repository: URL, includingAllRefs: Bool = false) async throws -> Int {
        var arguments = ["rev-list", "--count"]
        arguments.append(includingAllRefs ? "--all" : "HEAD")

        let result = try await runReturningResult(arguments, in: repository, allowsOptionalLocks: false)
        guard result.isSuccess else { return 0 }

        let text = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(text) ?? 0
    }
}
