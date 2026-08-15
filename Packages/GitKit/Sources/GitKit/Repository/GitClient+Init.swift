import Foundation

/// 在某个目录建仓库之前发现的问题。
public enum InitObstacle: Sendable, Equatable {

    /// 这个目录本身已经是一个 git 仓库。
    ///
    /// 直接 `git init` 不会报错——它会打印 "Reinitialized existing Git repository"
    /// 并**以 0 退出**。用户以为自己新建了一个仓库，其实只是把已有的重新初始化了一遍。
    case alreadyARepository

    /// 这个目录在另一个仓库里面。
    ///
    /// 照做的话会得到一个**嵌套仓库**：里层是独立仓库，外层只把它看成一个
    /// 未跟踪的目录，`git add` 进去还会变成 submodule 的雏形。
    /// 这几乎从来不是用户想要的，但 git 一声不吭就做了。
    case insideRepository(root: String)

    /// 目录里已经有文件。不是错误，但值得说一声：
    /// 那些文件会立刻以「未跟踪」的身份出现在新仓库里。
    case directoryNotEmpty(fileCount: Int)

    public var isBlocking: Bool {
        switch self {
        case .alreadyARepository, .insideRepository: true
        case .directoryNotEmpty: false
        }
    }
}

extension GitClient {

    /// 在建仓库之前检查这个目录有没有问题。
    ///
    /// **必须先查。** `git init` 对「已经是仓库」和「在仓库里面」这两种情况
    /// 都不报错，用户拿不到任何提示。
    public func initObstacle(at directory: URL) async -> InitObstacle? {
        let manager = FileManager.default

        if manager.fileExists(atPath: directory.appendingPathComponent(".git").path) {
            return .alreadyARepository
        }

        // 目录还不存在时上溯到最近的存在的父目录去问，否则 git 直接报路径不存在
        var probe = directory
        while !manager.fileExists(atPath: probe.path), probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        if let result = try? await runReturningResult(
            ["rev-parse", "--show-toplevel"], in: probe, allowsOptionalLocks: false),
            result.isSuccess
        {
            let root = result.standardOutputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !root.isEmpty {
                return .insideRepository(root: root)
            }
        }

        let contents =
            (try? manager.contentsOfDirectory(atPath: directory.path))?
            .filter { $0 != ".DS_Store" } ?? []
        if !contents.isEmpty {
            return .directoryNotEmpty(fileCount: contents.count)
        }

        return nil
    }
}

extension GitOperation {

    /// 在一个目录里建新仓库。
    ///
    /// - Parameter initialBranch: **一律显式给出**。不给的话默认分支名取决于
    ///   用户的 `init.defaultBranch` 配置，同一个 app 在两台机器上会建出
    ///   `main` 和 `master` 两种仓库——而这个名字之后到处都要用到。
    public static func initRepository(initialBranch: String = "main") -> GitOperation {
        GitOperation(
            kind: .initRepository,
            arguments: ["init", "--initial-branch", initialBranch],
            summary: "新建仓库（默认分支 \(initialBranch)）",
            explanation: "在这个目录里建一个空仓库，默认分支叫 \(initialBranch)。"
                + "目录里已有的文件不会被自动纳入，它们会以「未跟踪」的身份出现，"
                + "由你决定哪些要提交。",
            hazard: .none
        )
    }
}
