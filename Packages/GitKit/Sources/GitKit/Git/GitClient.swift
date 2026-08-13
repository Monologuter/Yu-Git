import Foundation

/// git CLI 的调用入口。
///
/// 驭Git 不用 libgit2，而是调用系统 git——这是唯一能让用户既有的 credential helper、
/// SSH config、hooks 与第三方工具原样生效的方案。代价是必须把 CLI 的每个坑都堵住：
/// 环境隔离、禁止交互、路径转义、锁竞争，都在这一层处理。
public struct GitClient: Sendable {

    public let executable: URL
    public let environment: [String: String]

    private let runner = ProcessRunner()

    public init(executable: URL, environment: [String: String]? = nil) {
        self.executable = executable
        self.environment = environment ?? Self.makeEnvironment()
    }

    /// 用系统上找到的 git 创建客户端。
    /// - Throws: 找不到 git 时抛出 ``GitError/executableNotFound``。
    public init(environment: [String: String]? = nil) throws {
        guard let located = GitExecutable.locate() else {
            throw GitError.executableNotFound
        }
        self.init(executable: located, environment: environment)
    }

    // MARK: - 执行

    /// 在指定仓库中执行一条 git 命令。
    ///
    /// - Parameter allowsOptionalLocks: 传 `false` 会加上 `--no-optional-locks`，
    ///   让 git 放弃刷新 index 缓存。**后台自动刷新必须传 false**，否则会与用户
    ///   终端里的 git 抢 `index.lock`。用户主动触发的操作保持 `true` 以获得缓存加速。
    /// - Throws: 非零退出码会抛出 ``GitError/commandFailed(arguments:exitCode:standardError:)``。
    ///   注意有些命令用退出码表达业务语义（如 `diff --quiet` 的 1 表示「有改动」），
    ///   这类调用应改用 ``runReturningResult(_:in:allowsOptionalLocks:standardInput:timeout:)``。
    @discardableResult
    public func run(
        _ arguments: [String],
        in repository: URL,
        allowsOptionalLocks: Bool = true,
        additionalEnvironment: [String: String] = [:],
        standardInput: Data? = nil,
        timeout: Duration? = .seconds(60)
    ) async throws -> ProcessResult {
        let result = try await runReturningResult(
            arguments,
            in: repository,
            allowsOptionalLocks: allowsOptionalLocks,
            additionalEnvironment: additionalEnvironment,
            standardInput: standardInput,
            timeout: timeout
        )
        guard result.isSuccess else {
            throw GitError.commandFailed(
                arguments: arguments,
                exitCode: result.exitCode,
                standardError: result.standardErrorText
            )
        }
        return result
    }

    /// 同 ``run(_:in:allowsOptionalLocks:additionalEnvironment:standardInput:timeout:)``，
    /// 但非零退出码原样返回而不抛错。
    ///
    /// - Parameter additionalEnvironment: 只对这一条命令生效的环境变量，会覆盖同名的默认值。
    ///   典型用途是 `GIT_INDEX_FILE`——时间线快照要用独立 index 把工作区写成 tree，
    ///   绝不能污染仓库真正的 index。
    /// - Parameter onStandardErrorChunk: stderr 每来一段就回调一次。fetch / push 的进度
    ///   写在 stderr 且用 `\r` 原地刷新，等到命令结束再读就只剩最后一行了。
    public func runReturningResult(
        _ arguments: [String],
        in repository: URL,
        allowsOptionalLocks: Bool = true,
        additionalEnvironment: [String: String] = [:],
        standardInput: Data? = nil,
        timeout: Duration? = .seconds(60),
        onStandardErrorChunk: (@Sendable (Data) -> Void)? = nil
    ) async throws -> ProcessResult {
        var full = ["-C", repository.path]
        if !allowsOptionalLocks {
            full.append("--no-optional-locks")
        }
        full += Self.globalConfiguration
        full += arguments

        var effectiveEnvironment = environment
        effectiveEnvironment.merge(additionalEnvironment) { _, override in override }

        return try await runner.run(
            executable: executable,
            arguments: full,
            workingDirectory: repository,
            environment: effectiveEnvironment,
            standardInput: standardInput,
            timeout: timeout,
            onStandardErrorChunk: onStandardErrorChunk
        )
    }

    // MARK: - 仓库

    /// 返回包含给定路径的仓库根目录。
    ///
    /// - Note: 返回值显式标记为目录 URL（带尾随斜杠）。比较两个仓库是否是同一个时
    ///   请用 `path` 或 `standardizedFileURL`——尾随斜杠不同的 URL 并不相等，
    ///   直接用 `==` 或拿 URL 当字典 key 会踩坑。
    public func repositoryRoot(containing path: URL) async throws -> URL {
        let result = try await runReturningResult(["rev-parse", "--show-toplevel"], in: path)
        guard result.isSuccess else {
            throw GitError.notARepository(path: path.path)
        }
        let root = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: root, isDirectory: true)
    }

    /// 读取仓库当前状态。
    ///
    /// - Parameter untrackedFiles: 默认 ``UntrackedFilesMode/all``——GUI 要能逐个文件
    ///   暂存，只报告目录不够用。未跟踪文件极多的仓库上可降为 ``UntrackedFilesMode/normal``。
    public func status(
        of repository: URL,
        untrackedFiles: UntrackedFilesMode = .all,
        includeIgnored: Bool = false
    ) async throws -> RepositoryStatus {
        let arguments = [
            "status",
            "--porcelain=v2",
            "--branch",
            "-z",
            "--untracked-files=\(untrackedFiles.rawValue)",
            "--ignored=\(includeIgnored ? "matching" : "no")",
        ]

        // 读状态属于随时可能被 FSEvents 触发的高频操作，不与用户的终端抢锁。
        let result = try await run(arguments, in: repository, allowsOptionalLocks: false)
        return try StatusParser.parse(result.standardOutput)
    }

    public enum UntrackedFilesMode: String, Sendable {
        /// 完全不报告未跟踪文件。
        case none = "no"
        /// 只报告未跟踪的目录本身，不展开其中的文件。
        case normal
        /// 展开未跟踪目录下的每个文件。
        case all
    }

    // MARK: - 环境

    /// 每条命令都会带上的全局配置。
    ///
    /// - `core.quotepath=false`：非 ASCII 路径不转义成 `\xxx`（配合 `-z` 才能拿到原始字节）
    /// - `color.ui=false`：避免任何情况下混入 ANSI 颜色码干扰解析
    private static let globalConfiguration = [
        "-c", "core.quotepath=false",
        "-c", "color.ui=false",
    ]

    /// 从父进程环境派生出安全的 git 执行环境。
    public static func makeEnvironment(
        basedOn base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base

        // 若 App 是被 git hook 或某个仓库里的终端拉起的，这些变量会被继承，
        // 导致我们的每条命令都作用到**错误的仓库**上。必须清干净。
        for key in repositoryScopedKeys {
            environment.removeValue(forKey: key)
        }

        environment["GIT_TERMINAL_PROMPT"] = "0"  // 绝不弹交互提示，宁可失败也不能挂起
        environment["GIT_PAGER"] = "cat"  // pager 会等待翻页输入
        environment["GIT_EDITOR"] = "true"  // 需要编辑器的命令直接返回成功

        return environment
    }

    /// 会把 git 指向特定仓库的环境变量，必须从继承环境中剔除。
    ///
    /// 注意不含 `GIT_CONFIG_GLOBAL` / `GIT_CONFIG_SYSTEM`：那两个是用户有意设置的
    /// 配置文件位置，不是仓库指向，保留。
    private static let repositoryScopedKeys = [
        "GIT_DIR",
        "GIT_WORK_TREE",
        "GIT_INDEX_FILE",
        "GIT_COMMON_DIR",
        "GIT_OBJECT_DIRECTORY",
        "GIT_ALTERNATE_OBJECT_DIRECTORIES",
        "GIT_CONFIG",
        "GIT_CONFIG_PARAMETERS",
        "GIT_PREFIX",
        "GIT_NAMESPACE",
    ]
}
