import Foundation

extension GitClient {

    /// 列出分支。
    ///
    /// - Parameter includingRemote: 为 `true` 时一并列出远程跟踪分支。
    public func branches(in repository: URL, includingRemote: Bool = true) async throws -> [Branch] {
        var arguments = ["for-each-ref", "--format=\(RefParser.branchFormat)", "refs/heads"]
        if includingRemote {
            arguments.append("refs/remotes")
        }

        let result = try await run(arguments, in: repository, allowsOptionalLocks: false)
        return try RefParser.parseBranches(result.standardOutput)
    }

    /// 当前所在分支；detached HEAD 或空仓库时为 nil。
    public func currentBranch(in repository: URL) async throws -> Branch? {
        try await branches(in: repository, includingRemote: false).first { $0.isCurrent }
    }

    /// 列出所有 tag。
    ///
    /// - Parameter sortedByDate: 默认按创建时间倒序（新的在前）。传 `false` 则按名称排序，
    ///   注意那是字典序——`v0.10.0` 会排在 `v0.9.0` 前面。
    public func tags(in repository: URL, sortedByDate: Bool = true) async throws -> [Tag] {
        let arguments = [
            "for-each-ref",
            "--format=\(RefParser.tagFormat)",
            "--sort=\(sortedByDate ? "-creatordate" : "refname")",
            "refs/tags",
        ]

        let result = try await run(arguments, in: repository, allowsOptionalLocks: false)
        return try RefParser.parseTags(result.standardOutput)
    }
}
