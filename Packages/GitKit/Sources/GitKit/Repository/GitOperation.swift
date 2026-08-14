import Foundation

/// 一次仓库写操作的完整描述。
///
/// 驭Git 的**所有**写操作都必须先表达成 `GitOperation`，再交给 ``RepoActor/perform(_:standardInput:)``
/// 执行。这条约束换来三件事：
///
/// 1. **时间线 Undo**（支柱 1）要求每个操作可记录、可命名、可逆推——绕过入口直接跑
///    git 的写操作，就是时间线上一个补不回来的洞。
/// 2. **透明命令层**要求随时能展示「这一步等价于哪条 git 命令」。元数据跟操作长在
///    一起，而不是事后给每个按钮补文案。
/// 3. Command Palette 与教学模式消费的是同一份元数据，不会各写一套。
///
/// - Note: 需要从 stdin 传入的数据（如 patch）**不放在这里**，而是作为 `perform` 的
///   单独参数。patch 内容就是用户的代码，工程规范 §7 要求操作日志不含文件内容，
///   而这个类型是要被序列化进日志的。
public struct GitOperation: Sendable, Equatable, Codable {

    public enum Kind: String, Sendable, Equatable, Codable {
        case stage
        case unstage
        case stagePartial
        case unstagePartial
        case discard
        case commit
        case amend
        case stashPush
        case stashPop
        case createBranch
        case switchBranch
        case deleteBranch
        case renameBranch
        case merge
        case setUpstream
        case interactiveRebase
        case cherryPick
        case revert
        // reset 的三种模式各占一个 kind 而不是共用一个带参数的。
        // 它们的后果差得太远——`--soft` 什么都不丢，`--hard` 会丢掉未提交的改动，
        // 而时间线是按 kind 决定要不要拍快照的。
        case resetSoft
        case resetMixed
        case resetHard
        case createTag
        case deleteTag
        case pushTag
        case deleteRemoteTag
    }

    /// 操作的危险程度。时间线据此决定执行前是否必须打快照。
    public enum Hazard: String, Sendable, Equatable, Codable {
        /// 安全：随时能用 git 自身的命令回退。
        case none
        /// 改写已有历史（amend、rebase、reset）。原提交还能靠 reflog 找回，但引用已变。
        case rewritesHistory
        /// **丢弃未提交的内容**。这类改动从未进过 git 的对象库，reflog 也救不回来——
        /// 时间线快照是唯一的退路，因此是最需要兜底的一类。
        case discardsUncommittedWork
    }

    public let kind: Kind

    /// 传给 git 的实际参数，不含 `-C` 与全局配置（那些由 ``GitClient`` 统一附加）。
    public let arguments: [String]

    /// 给用户看的一句话中文摘要，如「暂存 3 个文件」。
    public let summary: String

    /// 中文注解：这条 git 命令到底做了什么。教学模式与透明命令层展示它。
    public let explanation: String

    public let hazard: Hazard

    /// 等价的 git 命令行，可直接复制到终端执行。
    public var equivalentCommand: String {
        "git " + arguments.map(Self.shellQuoted).joined(separator: " ")
    }

    /// 仅用于展示：含空格或 shell 元字符的参数套单引号。
    ///
    /// 实际执行时参数是按数组传给 `posix_spawn` 的，不经过 shell，因此**不需要**
    /// 也**不能**带这层引号。
    private static func shellQuoted(_ argument: String) -> String {
        let needsQuoting =
            argument.isEmpty
            || argument.contains { character in
                " \t\n'\"$`\\*?[]{}()<>|&;#~!".contains(character)
            }
        guard needsQuoting else { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}

// MARK: - 暂存与撤销

extension GitOperation {

    /// 把指定文件的当前内容整个放进 index。
    public static func stage(paths: [String]) -> GitOperation {
        GitOperation(
            kind: .stage,
            // `--` 之后的一律按路径解析，否则以 `-` 开头的文件名会被当成选项
            arguments: ["add", "--"] + paths,
            summary: paths.count == 1 ? "暂存 \(paths[0])" : "暂存 \(paths.count) 个文件",
            explanation: "把这些文件的当前内容放进 index（暂存区），下次提交时会包含它们。",
            hazard: .none
        )
    }

    /// 把文件从 index 中撤下，工作区内容保持不变。
    public static func unstage(paths: [String]) -> GitOperation {
        GitOperation(
            kind: .unstage,
            // restore --staged 用 HEAD 的内容覆盖 index，工作区不受影响。
            // 仓库还没有任何提交时没有 HEAD 可参照，调用方需改用 `rm --cached`。
            arguments: ["restore", "--staged", "--"] + paths,
            summary: paths.count == 1 ? "取消暂存 \(paths[0])" : "取消暂存 \(paths.count) 个文件",
            explanation: "把这些文件从 index 中撤下，工作区里的改动原样保留。",
            hazard: .none
        )
    }

    /// 暂存文件中选中的部分改动。patch 由 ``PatchBuilder`` 生成，经 stdin 传入。
    public static func stagePartial(path: String, changeCount: Int) -> GitOperation {
        GitOperation(
            kind: .stagePartial,
            arguments: ["apply", "--cached", "-"],
            summary: "暂存 \(path) 中的 \(changeCount) 处改动",
            explanation: "只把选中的那部分改动写入 index，其余改动仍留在工作区。"
                + "patch 由驭Git 生成并经标准输入交给 git。",
            hazard: .none
        )
    }

    /// 取消暂存文件中选中的部分改动。
    public static func unstagePartial(path: String, changeCount: Int) -> GitOperation {
        GitOperation(
            kind: .unstagePartial,
            arguments: ["apply", "--cached", "--reverse", "-"],
            summary: "取消暂存 \(path) 中的 \(changeCount) 处改动",
            explanation: "把选中的那部分改动从 index 中反向撤销，工作区内容不变。",
            hazard: .none
        )
    }

    /// 丢弃工作区中的改动，恢复成 index 里的内容。
    public static func discard(paths: [String]) -> GitOperation {
        GitOperation(
            kind: .discard,
            arguments: ["restore", "--"] + paths,
            summary: paths.count == 1 ? "丢弃 \(paths[0]) 的改动" : "丢弃 \(paths.count) 个文件的改动",
            explanation: "用 index 中的内容覆盖工作区。**被丢弃的改动没有进过 git 的对象库，"
                + "git 自身无法找回**，只能靠驭Git 的时间线快照恢复。",
            hazard: .discardsUncommittedWork
        )
    }
}

// MARK: - 提交

extension GitOperation {

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
            hazard: amend ? .rewritesHistory : .none
        )
    }
}

// MARK: - stash

extension GitOperation {

    /// 把当前改动收进 stash，工作区回到干净状态。
    public static func stashPush(message: String? = nil, includingUntracked: Bool = false) -> GitOperation {
        var arguments = ["stash", "push"]
        if includingUntracked {
            arguments.append("--include-untracked")
        }
        if let message, !message.isEmpty {
            arguments += ["--message", message]
        }

        return GitOperation(
            kind: .stashPush,
            arguments: arguments,
            summary: message.map { "暂存改动到 stash：\($0)" } ?? "暂存改动到 stash",
            explanation: "把工作区与 index 的改动收进 stash 栈，工作区恢复到 HEAD 的状态。"
                + (includingUntracked ? "未跟踪的文件也一并收入。" : "未跟踪的文件不受影响。"),
            hazard: .none
        )
    }

    /// 取回最近一次 stash 并从栈中移除。
    public static func stashPop(index: Int = 0) -> GitOperation {
        GitOperation(
            kind: .stashPop,
            arguments: ["stash", "pop", "stash@{\(index)}"],
            summary: "取回 stash@{\(index)}",
            explanation: "把这条 stash 的改动应用回工作区，并从 stash 栈中删除它。"
                + "若与当前改动冲突，stash 会保留在栈中等待处理。",
            hazard: .none
        )
    }
}
