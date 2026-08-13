import Foundation

/// 驭Git 在用户仓库里占用的命名空间。
///
/// 工程规范 §7 规定只能往两个地方写：这里集中定义，避免散落各处后失控。
/// 两者都在仓库内部——仓库被移动或删除时数据跟着走、跟着消失，不留孤儿。
public enum GitNamespace {

    /// 快照引用的前缀。
    ///
    /// 放在 `refs/yugit/` 而非 `refs/heads/` 或 stash 栈：
    /// - 不会被 `git push` 推到远程（push 默认只推 refs/heads 与 refs/tags）
    /// - 不出现在 `git branch`、`git stash list` 里
    /// - 但只要 ref 存在，对象就不会被 gc 回收
    ///
    /// 代价是 `git log --all` **会**包含它们，所以每处历史查询都必须显式 `--exclude`，
    /// 否则快照会混进用户看到的历史里。
    public static let refPrefix = "refs/yugit/"

    /// 时间线快照的引用前缀。
    public static let timelineRefPrefix = refPrefix + "timeline/"

    /// 私有数据目录名，位于 `<git-common-dir>/` 下。
    public static let directoryName = "yugit"

    /// 定位私有数据目录，必要时创建。
    ///
    /// 用 `--git-common-dir` 而非 `--git-dir`：同一仓库的多个 worktree 要共享
    /// 同一条时间线（支柱 3 的并行 agent 面板需要看到所有 worktree 的操作）。
    ///
    /// 临时文件也必须放在这里，**不能放工作区**——放工作区会变成未跟踪文件，
    /// 既出现在变更列表里，还会被快照自己收进去。
    public static func directory(in repository: URL, client: GitClient) async throws -> URL {
        let result = try await client.run(["rev-parse", "--git-common-dir"], in: repository)
        let raw = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)

        let gitDirectory =
            raw.hasPrefix("/")
            ? URL(fileURLWithPath: raw, isDirectory: true)
            : repository.appendingPathComponent(raw, isDirectory: true)

        let directory = gitDirectory.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
