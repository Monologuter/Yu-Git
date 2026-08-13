import Foundation

/// 一次仓库写操作的完整描述。
///
/// 驭Git 的**所有**写操作都必须先表达成 `GitOperation`，再交给 ``RepoActor/perform(_:)``
/// 执行。这条约束换来三件事：
///
/// 1. **时间线 Undo**（支柱 1）要求每个操作可记录、可命名、可逆推——绕过入口直接跑
///    git 的写操作，就是时间线上一个补不回来的洞。
/// 2. **透明命令层**要求随时能展示「这一步等价于哪条 git 命令」。元数据跟操作长在
///    一起，而不是事后给每个按钮补文案。
/// 3. Command Palette 与教学模式消费的是同一份元数据，不会各写一套。
public struct GitOperation: Sendable, Equatable, Codable {

    public enum Kind: String, Sendable, Equatable, Codable {
        case stage
        case commit
        case amend
    }

    public let kind: Kind

    /// 传给 git 的实际参数，不含 `-C` 与全局配置（那些由 ``GitClient`` 统一附加）。
    public let arguments: [String]

    /// 给用户看的一句话中文摘要，如「暂存 3 个文件」。
    public let summary: String

    /// 中文注解：这条 git 命令到底做了什么。教学模式与透明命令层展示它。
    public let explanation: String

    /// 会改写已有历史。时间线必须在执行这类操作前打快照（v0.5）。
    public let rewritesHistory: Bool

    /// 等价的 git 命令行，可直接复制到终端执行。
    public var equivalentCommand: String {
        "git " + arguments.map(Self.shellQuoted).joined(separator: " ")
    }

    /// 仅用于展示：含空格或 shell 元字符的参数套单引号。
    ///
    /// 实际执行时参数是按数组传给 `posix_spawn` 的，不经过 shell，因此**不需要**
    /// 也**不能**带这层引号。
    private static func shellQuoted(_ argument: String) -> String {
        let needsQuoting = argument.isEmpty || argument.contains { character in
            " \t\n'\"$`\\*?[]{}()<>|&;#~!".contains(character)
        }
        guard needsQuoting else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

// MARK: - 具体操作

extension GitOperation {

    /// 把指定文件的当前内容放进 index。
    public static func stage(paths: [String]) -> GitOperation {
        GitOperation(
            kind: .stage,
            // `--` 之后的一律按路径解析，否则以 `-` 开头的文件名会被当成选项。
            arguments: ["add", "--"] + paths,
            summary: paths.count == 1 ? "暂存 \(paths[0])" : "暂存 \(paths.count) 个文件",
            explanation: "把这些文件的当前内容放进 index（暂存区），下次提交时会包含它们。",
            rewritesHistory: false
        )
    }

    /// 把 index 中的内容记录为一条 commit。
    ///
    /// - Parameter amend: 为 `true` 时替换上一条 commit 而非新建。
    public static func commit(message: String, amend: Bool = false) -> GitOperation {
        var arguments = ["commit", "--message", message]
        if amend {
            arguments.append("--amend")
        }

        return GitOperation(
            kind: amend ? .amend : .commit,
            arguments: arguments,
            summary: amend ? "修改上一条提交" : "提交暂存的改动",
            explanation: amend
                ? "用当前 index 的内容替换上一条 commit。这会生成新的 commit hash，"
                    + "已推送的提交若被 amend，再推送就需要 force。"
                : "把 index（暂存区）中的内容记录为一条新的 commit。",
            rewritesHistory: amend
        )
    }
}
