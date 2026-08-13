import Foundation

/// 一个远程仓库配置。
public struct Remote: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let fetchURL: String
    public let pushURL: String

    public init(name: String, fetchURL: String, pushURL: String) {
        self.name = name
        self.fetchURL = fetchURL
        self.pushURL = pushURL
    }

    /// 用 SSH 协议（`git@host:path` 或 `ssh://`）。
    public var usesSSH: Bool {
        fetchURL.hasPrefix("ssh://")
            || (fetchURL.contains("@") && fetchURL.contains(":"))
                && !fetchURL.hasPrefix("http")
    }
}

extension GitClient {

    /// 列出远程仓库。
    public func remotes(in repository: URL) async throws -> [Remote] {
        let result = try await run(["remote", "--verbose"], in: repository, allowsOptionalLocks: false)

        // 每个远程有 fetch 与 push 两行：`origin\thttps://...(fetch)`
        var fetchURLs: [String: String] = [:]
        var pushURLs: [String: String] = [:]

        for line in result.standardOutputText.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = String(parts[0])
            let remainder = parts[1]
            guard let space = remainder.lastIndex(of: " ") else { continue }
            let url = String(remainder[remainder.startIndex..<space])
            let kind = remainder[space...].trimmingCharacters(in: .whitespaces)

            if kind == "(fetch)" {
                fetchURLs[name] = url
            } else if kind == "(push)" {
                pushURLs[name] = url
            }
        }

        return fetchURLs.keys.sorted().map { name in
            Remote(
                name: name,
                fetchURL: fetchURLs[name] ?? "",
                pushURL: pushURLs[name] ?? fetchURLs[name] ?? ""
            )
        }
    }

    /// 执行一条会访问网络的 git 命令，实时报告进度。
    ///
    /// - Parameters:
    ///   - onProgress: 进度回调，可能来自任意线程。
    ///   - timeout: 网络操作默认给 5 分钟——大仓库的首次 clone 可能很久，
    ///     但也不能没有上限，否则卡住的连接会永远挂着。
    /// - Throws: 失败时抛 ``RemoteFailure``，其中带中文说明与下一步建议。
    func runNetworkCommand(
        _ arguments: [String],
        in repository: URL,
        onProgress: (@Sendable (TransferProgress) -> Void)? = nil,
        timeout: Duration? = .seconds(300)
    ) async throws -> ProcessResult {
        // git 只在检测到终端时才输出进度，这里必须显式要求
        var full = arguments
        if !full.contains("--progress") {
            full.append("--progress")
        }

        let progressHandler: (@Sendable (Data) -> Void)?
        if let onProgress {
            // 解析器要跨线程累积状态，用锁保护
            let parser = ProgressParserBox()
            progressHandler = { chunk in
                for progress in parser.consume(chunk) {
                    onProgress(progress)
                }
            }
        } else {
            progressHandler = nil
        }

        let result = try await runReturningResult(
            full,
            in: repository,
            allowsOptionalLocks: false,
            timeout: timeout,
            onStandardErrorChunk: progressHandler
        )

        guard result.isSuccess else {
            throw RemoteFailure.diagnose(
                standardError: result.standardErrorText,
                arguments: arguments
            )
        }
        return result
    }

    /// 从远程拉取引用与对象，不改动工作区。
    public func fetch(
        in repository: URL,
        remote: String? = nil,
        pruneDeletedBranches: Bool = true,
        fetchTags: Bool = true,
        onProgress: (@Sendable (TransferProgress) -> Void)? = nil
    ) async throws {
        var arguments = ["fetch"]
        if pruneDeletedBranches {
            // 远程已删除的分支，本地的跟踪引用也一并清掉，否则分支列表里全是幽灵
            arguments.append("--prune")
        }
        if fetchTags {
            arguments.append("--tags")
        }
        arguments.append(remote ?? "--all")

        _ = try await runNetworkCommand(arguments, in: repository, onProgress: onProgress)
    }

    /// 拉取并合并到当前分支。
    ///
    /// - Parameter rebase: 用 rebase 代替 merge，历史更线性。
    public func pull(
        in repository: URL,
        rebase: Bool = false,
        onProgress: (@Sendable (TransferProgress) -> Void)? = nil
    ) async throws {
        var arguments = ["pull"]
        if rebase {
            arguments.append("--rebase")
        }
        _ = try await runNetworkCommand(arguments, in: repository, onProgress: onProgress)
    }

    /// 推送到远程。
    ///
    /// - Parameters:
    ///   - setUpstream: 首次推送新分支时设置 upstream。
    ///   - forceWithLease: 带租约的强推。**绝不提供无租约的 `--force`**——
    ///     后者会直接覆盖别人推上去的提交，而 `--force-with-lease` 在远程有
    ///     未知新提交时会拒绝。
    public func push(
        in repository: URL,
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool = false,
        forceWithLease: Bool = false,
        pushTags: Bool = false,
        onProgress: (@Sendable (TransferProgress) -> Void)? = nil
    ) async throws {
        var arguments = ["push"]
        if setUpstream {
            arguments.append("--set-upstream")
        }
        if forceWithLease {
            arguments.append("--force-with-lease")
        }
        if pushTags {
            arguments.append("--tags")
        }
        if let remote {
            arguments.append(remote)
            if let branch {
                arguments.append(branch)
            }
        }

        _ = try await runNetworkCommand(arguments, in: repository, onProgress: onProgress)
    }

    /// 克隆仓库到指定目录。
    public func clone(
        from url: String,
        to destination: URL,
        onProgress: (@Sendable (TransferProgress) -> Void)? = nil
    ) async throws {
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        _ = try await runNetworkCommand(
            ["clone", url, destination.path],
            in: parent,
            onProgress: onProgress
        )
    }
}

/// 让进度解析器能在 `@Sendable` 回调里累积状态。
///
/// 回调来自读取 stderr 的后台线程，同一时刻只有一个线程在调用，
/// 但编译器不知道这一点，用锁把它说清楚。
private final class ProgressParserBox: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = TransferProgressParser()

    func consume(_ data: Data) -> [TransferProgress] {
        lock.withLock { parser.consume(data) }
    }
}
