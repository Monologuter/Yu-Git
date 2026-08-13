import Foundation

extension GitClient {

    /// 读取提交历史。
    ///
    /// - Parameters:
    ///   - includingAllRefs: 为 `true` 时列出所有引用可达的提交（`--all`），
    ///     而不只是当前 HEAD 这条线——GUI 的分支图需要看到全部分支。
    ///   - maxCount / skip: 分页。5 万 commit 的仓库不能一次全读进来。
    public func log(
        in repository: URL,
        includingAllRefs: Bool = false,
        maxCount: Int? = nil,
        skip: Int? = nil,
        paths: [String] = []
    ) async throws -> [Commit] {
        var arguments = [
            "log",
            "--format=\(LogParser.format)",
            // 输出 refs/heads/main 这样的完整路径；短名无法区分同名的分支与 tag
            "--decorate=full",
            // 拓扑序：父提交永远排在子提交之后。按时间排会让分支图出现视觉上的交叉错乱
            "--topo-order",
        ]
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
