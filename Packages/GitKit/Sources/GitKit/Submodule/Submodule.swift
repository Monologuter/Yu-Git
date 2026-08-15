import Foundation

/// 一个子模块。
public struct Submodule: Sendable, Equatable, Identifiable {

    /// 子模块在父仓库里的路径。
    public let path: String
    /// 父仓库记录的那个 commit。
    public let recordedCommit: String
    /// 子模块目录里实际签出的引用描述，如 `heads/main` 或 `v1.2.0`。
    /// 没初始化时为空。
    public let describedRef: String
    public let state: State

    public var id: String { path }

    /// `git submodule status` 每行开头那个字符。
    public enum State: Sendable, Equatable {
        /// 一切正常：签出的就是父仓库记录的那个 commit。
        case current
        /// **没初始化。** 目录是空的——克隆父仓库时不带 `--recursive` 就是这个状态，
        /// 而这正是「代码拉下来编译不过」最常见的原因之一。
        case notInitialized
        /// 签出的 commit 和父仓库记录的不一致。
        case outOfSync
        /// 合并冲突还没解决。
        case conflicted

        public var displayName: String {
            switch self {
            case .current: "已同步"
            case .notInitialized: "未初始化"
            case .outOfSync: "与记录的版本不一致"
            case .conflicted: "有冲突"
            }
        }

        public var explanation: String {
            switch self {
            case .current:
                "子模块签出的正是父仓库记录的那个提交。"
            case .notInitialized:
                "子模块目录是空的。克隆父仓库时没带 `--recursive` 就会这样，"
                    + "而这是「代码拉下来编译不过」最常见的原因之一。更新一次就好。"
            case .outOfSync:
                "子模块当前签出的提交和父仓库记录的不是同一个。"
                    + "要么是你在子模块里切过分支，要么是父仓库更新了记录但还没同步过来。"
            case .conflicted:
                "合并时两边把子模块指向了不同的提交，需要先决定用哪一个。"
            }
        }

        /// 需要用户处理。
        public var needsAttention: Bool { self != .current }
    }

    public init(path: String, recordedCommit: String, describedRef: String, state: State) {
        self.path = path
        self.recordedCommit = recordedCommit
        self.describedRef = describedRef
        self.state = state
    }
}

/// 解析 `git submodule status` 的输出。
public enum SubmoduleParser {

    /// 每行形如：`<状态字符><hash> <路径> (<描述>)`
    ///
    /// 注意**状态字符是第一列，正常时是一个空格**——直接 trim 掉行首空白
    /// 会把「已同步」和别的状态混在一起，因为剩下的部分长得一模一样。
    public static func parse(_ text: String) -> [Submodule] {
        var result: [Submodule] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let marker = line.first else { continue }
            let state: Submodule.State =
                switch marker {
                case "-": .notInitialized
                case "+": .outOfSync
                case "U": .conflicted
                default: .current
                }

            let rest = line.dropFirst()
            // hash 和路径之间是一个空格；路径里可能有空格，所以只切第一个
            let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let hash = String(parts[0])

            var remainder = String(parts[1])
            var described = ""
            // 结尾的 (…) 是签出引用的描述。未初始化时没有这一段。
            if remainder.hasSuffix(")"), let open = remainder.lastIndex(of: "(") {
                described = String(
                    remainder[remainder.index(after: open)..<remainder.index(before: remainder.endIndex)])
                remainder = String(remainder[remainder.startIndex..<open])
            }

            let path = remainder.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty, !hash.isEmpty else { continue }

            result.append(
                Submodule(
                    path: path,
                    recordedCommit: hash,
                    describedRef: described,
                    state: state
                )
            )
        }

        return result
    }
}

extension GitClient {

    /// 列出全部子模块，含未初始化的。
    public func submodules(in repository: URL, recursive: Bool = false) async throws -> [Submodule] {
        var arguments = ["submodule", "status"]
        if recursive { arguments.append("--recursive") }

        let result = try await runReturningResult(
            arguments, in: repository, allowsOptionalLocks: false)
        guard result.isSuccess else { return [] }
        return SubmoduleParser.parse(result.standardOutputText)
    }
}

extension GitOperation {

    /// 把子模块更新到父仓库记录的那个提交。
    ///
    /// - Parameter path: 只更新某一个；nil 表示全部。
    /// - Parameter initializing: 带上 `--init`，顺手把没初始化的也拉下来。
    ///   默认开着——「更新」这个词在用户脑子里就包含「先弄下来」，
    ///   而没初始化恰恰是最常见的那种需要更新的状态。
    public static func updateSubmodules(
        path: String? = nil,
        initializing: Bool = true,
        recursive: Bool = true
    ) -> GitOperation {
        var arguments = ["submodule", "update"]
        if initializing { arguments.append("--init") }
        if recursive { arguments.append("--recursive") }
        if let path {
            arguments += ["--", path]
        }

        return GitOperation(
            kind: .updateSubmodule,
            arguments: arguments,
            summary: path.map { "更新子模块 \($0)" } ?? "更新全部子模块",
            explanation: "把子模块签出到父仓库记录的那个提交。"
                + (initializing ? "还没初始化的会先克隆下来。" : "")
                + "**子模块里未提交的改动会被保留**，但如果它和要签出的版本冲突，"
                + "这一步会失败而不是覆盖掉你的改动。",
            hazard: .none
        )
    }
}
