import Foundation

/// 单个文件的 diff。
///
/// 路径不从 diff 输出里解析——git 会对含引号、反斜杠、控制字符的路径加引用转义，
/// 即便设了 `core.quotepath=false` 也只免了非 ASCII 那部分。调用方本来就知道自己
/// 要看哪个文件，直接带进来更可靠。
public struct FileDiff: Sendable, Equatable {

    public enum Change: Sendable, Equatable {
        case added
        case deleted
        case modified
        case renamed(from: String)
        /// 只改了文件模式（如加上可执行位），内容没变。
        case modeChanged
    }

    public let path: String
    public let change: Change
    public let hunks: [DiffHunk]

    /// 二进制文件。git 不给出行级 diff，界面只能显示「二进制文件已变更」。
    public let isBinary: Bool

    public let oldMode: String?
    public let newMode: String?

    /// git 原始输出的文件头（`diff --git` 到 `+++` 那几行）。
    ///
    /// ``PatchBuilder`` 生成 patch 时原样复用它，而不是自己拼 `--- a/<path>`：
    /// git 对含空格、引号、反斜杠、非 ASCII 的路径有一套自己的引用规则
    /// （还会在路径后补 tab），照抄原文才不会在这些文件上出错。
    public let header: String

    public var addedLineCount: Int {
        hunks.reduce(0) { $0 + $1.lines.count(where: { $0.kind == .addition }) }
    }

    public var deletedLineCount: Int {
        hunks.reduce(0) { $0 + $1.lines.count(where: { $0.kind == .deletion }) }
    }

    /// 没有任何内容变化（可能只是模式变了，或者是空文件）。
    public var isEmpty: Bool { hunks.isEmpty }

    public init(
        path: String,
        change: Change,
        hunks: [DiffHunk],
        isBinary: Bool = false,
        oldMode: String? = nil,
        newMode: String? = nil,
        header: String = ""
    ) {
        self.path = path
        self.change = change
        self.hunks = hunks
        self.isBinary = isBinary
        self.oldMode = oldMode
        self.newMode = newMode
        self.header = header
    }
}

/// diff 中的一个变更块。
public struct DiffHunk: Sendable, Equatable, Identifiable {

    public var id: String { "\(oldStart),\(oldCount)-\(newStart),\(newCount)" }

    /// 对应 `@@ -oldStart,oldCount +newStart,newCount @@`。
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int

    /// `@@` 之后的那段提示文字，git 通常填所属函数名，方便定位。
    public let heading: String

    public let lines: [DiffLine]

    /// 还原成 `@@ -1,5 +1,6 @@` 形式。
    ///
    /// count 为 1 时 git 会省略它，生成 patch 时必须照做，否则 `git apply` 会拒绝。
    public var header: String {
        let old = oldCount == 1 ? "\(oldStart)" : "\(oldStart),\(oldCount)"
        let new = newCount == 1 ? "\(newStart)" : "\(newStart),\(newCount)"
        let base = "@@ -\(old) +\(new) @@"
        return heading.isEmpty ? base : "\(base) \(heading)"
    }

    public init(
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int,
        heading: String = "",
        lines: [DiffLine]
    ) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.heading = heading
        self.lines = lines
    }
}

/// diff 中的一行。
public struct DiffLine: Sendable, Equatable, Identifiable {

    public enum Kind: Sendable, Equatable {
        case context
        case addition
        case deletion

        /// 写进 patch 的前缀字符。
        public var prefix: Character {
            switch self {
            case .context: " "
            case .addition: "+"
            case .deletion: "-"
            }
        }
    }

    public var id: String { "\(oldLineNumber ?? -1):\(newLineNumber ?? -1):\(kind)" }

    public let kind: Kind
    /// 行内容，不含前缀字符，也不含结尾换行。
    public let text: String

    /// 在旧文件中的行号（1 起）；新增行为 nil。
    public let oldLineNumber: Int?
    /// 在新文件中的行号（1 起）；删除行为 nil。
    public let newLineNumber: Int?

    /// 这一行后面跟着 `\ No newline at end of file`。
    ///
    /// 必须原样保留：生成 patch 时漏掉这个标记，`git apply` 会给文件补上一个
    /// 本不存在的换行，工作区内容就被悄悄改坏了。
    public let isMissingNewline: Bool

    public init(
        kind: Kind,
        text: String,
        oldLineNumber: Int?,
        newLineNumber: Int?,
        isMissingNewline: Bool = false
    ) {
        self.kind = kind
        self.text = text
        self.oldLineNumber = oldLineNumber
        self.newLineNumber = newLineNumber
        self.isMissingNewline = isMissingNewline
    }
}
