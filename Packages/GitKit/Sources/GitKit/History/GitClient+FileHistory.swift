import Foundation

extension GitClient {

    /// 某个文件的全部改动记录。
    ///
    /// 用 `--follow` 跨过改名。不带它的话，历史会在改名那一刻**戛然而止**——
    /// 一个存在了三年、中途换过一次名字的文件，看起来像是上个月才被创建的。
    ///
    /// - Important: `--follow` **只接受一个 pathspec**，给两个会直接
    ///   `fatal: --follow requires exactly one pathspec`。所以这个方法只收单个路径，
    ///   而不是复用 ``log(in:includingAllRefs:order:maxCount:skip:paths:filter:)``
    ///   的 `paths` 数组。
    ///
    /// - Parameter follow: 关掉就只看这个路径本身的历史。有意义的场景是
    ///   「这个位置上曾经有过哪些文件」，而不是「这个文件经历了什么」。
    public func fileHistory(
        of path: String,
        in repository: URL,
        follow: Bool = true,
        maxCount: Int? = nil
    ) async throws -> [Commit] {
        var arguments = [
            "log",
            "--format=\(LogParser.format)",
            "--decorate=full",
        ]
        if follow {
            arguments.append("--follow")
        }
        if let maxCount {
            arguments.append("--max-count=\(maxCount)")
        }
        arguments += ["--", path]

        let result = try await runReturningResult(
            arguments, in: repository, allowsOptionalLocks: false)

        // 文件是新加还没提交过、或者路径打错了，都会得到空历史而不是错误
        guard result.isSuccess else {
            if result.standardErrorText.contains("does not have any commits yet") {
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
}

/// 两个分支之间差了什么。
public struct BranchComparison: Sendable, Equatable {

    /// 基准分支，通常是要合并进去的那个。
    public let base: String
    /// 被比较的分支。
    public let target: String

    /// `target` 有而 `base` 没有的提交，最新在前。
    public let ahead: [Commit]
    /// `base` 有而 `target` 没有的提交。
    public let behind: [Commit]

    /// 从共同祖先算起，`target` 改了哪些文件。
    public let files: [CommitFileChange]

    /// 两条分支的共同祖先。没有共同祖先（毫无关系的两条历史）时为 nil。
    public let mergeBase: String?

    public init(
        base: String,
        target: String,
        ahead: [Commit],
        behind: [Commit],
        files: [CommitFileChange],
        mergeBase: String?
    ) {
        self.base = base
        self.target = target
        self.ahead = ahead
        self.behind = behind
        self.files = files
        self.mergeBase = mergeBase
    }

    /// 两条分支是不是已经分叉了。
    public var hasDiverged: Bool { !ahead.isEmpty && !behind.isEmpty }
}

extension GitClient {

    /// 比较两个分支。
    ///
    /// - Important: 文件差异用的是**三点** `base...target`，不是两点。
    ///   两点比的是两个尖端，会把 `base` 独有的文件显示成「被删除」——
    ///   而那些文件根本不是 `target` 删的，它只是还没有它们。
    ///   一个刚从 main 分出来加了一个文件的分支，用两点看会显示成
    ///   「加了 1 个文件，删了 main 上后来加的 8 个」，完全不是那么回事。
    ///   三点从共同祖先算起，答的才是「这条分支干了什么」。
    public func compareBranches(
        base: String,
        target: String,
        in repository: URL,
        maxCount: Int = 500
    ) async throws -> BranchComparison {
        async let aheadCommits = revisionRange("\(base)..\(target)", in: repository, maxCount: maxCount)
        async let behindCommits = revisionRange("\(target)..\(base)", in: repository, maxCount: maxCount)
        async let changed = comparedFiles(base: base, target: target, in: repository)
        async let ancestor = mergeBase(base, target, in: repository)

        return BranchComparison(
            base: base,
            target: target,
            ahead: try await aheadCommits,
            behind: try await behindCommits,
            files: try await changed,
            mergeBase: try await ancestor
        )
    }

    private func revisionRange(
        _ range: String,
        in repository: URL,
        maxCount: Int
    ) async throws -> [Commit] {
        let result = try await runReturningResult(
            [
                "log", "--format=\(LogParser.format)", "--decorate=full",
                "--max-count=\(maxCount)", range,
            ],
            in: repository,
            allowsOptionalLocks: false
        )
        guard result.isSuccess else { return [] }
        return try LogParser.parse(result.standardOutput)
    }

    private func comparedFiles(
        base: String,
        target: String,
        in repository: URL
    ) async throws -> [CommitFileChange] {
        let result = try await runReturningResult(
            ["diff", "--name-status", "-z", "\(base)...\(target)"],
            in: repository,
            allowsOptionalLocks: false
        )
        guard result.isSuccess else { return [] }
        return NameStatusParser.parse(result.standardOutput)
    }

    /// 两个引用的共同祖先。
    ///
    /// 毫无关系的两条历史（`git merge-base` 退出码 1）返回 nil 而不是抛错——
    /// 那是个正常的答案，界面上要据此说明「这两条分支没有共同起点」。
    public func mergeBase(
        _ first: String,
        _ second: String,
        in repository: URL
    ) async throws -> String? {
        let result = try await runReturningResult(
            ["merge-base", first, second], in: repository, allowsOptionalLocks: false)
        guard result.isSuccess else { return nil }
        let hash = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return hash.isEmpty ? nil : hash
    }
}
