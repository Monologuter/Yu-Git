import Foundation

extension GitClient {

    /// 写入 commit-graph 缓存。
    ///
    /// 拓扑排序要求 git 遍历完整提交图，5 万 commit 上取首屏也要 370ms；
    /// 有了这份缓存则降到 40ms。分支图必须用拓扑序才不会画错，所以这份缓存
    /// 是历史界面达到 PRD 性能指标的前提。
    ///
    /// 这是 git 官方的加速机制（`gc.writeCommitGraph` 默认就会写），文件落在
    /// `.git/objects/info/commit-graph`，属于纯缓存——删掉不影响仓库正确性，
    /// 也不改动任何用户配置，符合工程规范 §7 的「不擅改用户 git 环境」。
    public func writeCommitGraph(in repository: URL) async throws {
        _ = try await runReturningResult(
            ["commit-graph", "write", "--reachable", "--no-progress"],
            in: repository,
            allowsOptionalLocks: false,
            timeout: .seconds(120)
        )
    }

    /// 这个仓库是否已有 commit-graph 缓存。
    public func hasCommitGraph(in repository: URL) async -> Bool {
        guard
            let result = try? await runReturningResult(
                ["rev-parse", "--git-path", "objects/info/commit-graph"],
                in: repository,
                allowsOptionalLocks: false
            ), result.isSuccess
        else {
            return false
        }

        let raw = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = raw.hasPrefix("/") ? raw : repository.appendingPathComponent(raw).path
        return FileManager.default.fileExists(atPath: path)
    }
}
