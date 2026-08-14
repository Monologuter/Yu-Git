import Foundation

/// 一次提交里对一个文件做的事。
public struct CommitFileChange: Sendable, Equatable, Identifiable, Hashable {

    public enum Kind: Sendable, Equatable, Hashable {
        case added
        case modified
        case deleted
        /// 重命名，附带相似度（0…100）。
        case renamed(from: String, similarity: Int)
        /// 复制，附带来源。
        case copied(from: String, similarity: Int)
        case typeChanged
        /// git 给了个我们不认识的状态字母。原样留着，总比丢掉强。
        case other(String)

        public var displayName: String {
            switch self {
            case .added: "新增"
            case .modified: "修改"
            case .deleted: "删除"
            case .renamed: "重命名"
            case .copied: "复制"
            case .typeChanged: "类型变化"
            case let .other(code): code
            }
        }

        /// 列表里那个状态字母。
        public var letter: String {
            switch self {
            case .added: "A"
            case .modified: "M"
            case .deleted: "D"
            case .renamed: "R"
            case .copied: "C"
            case .typeChanged: "T"
            case let .other(code): String(code.prefix(1))
            }
        }
    }

    public let path: String
    public let kind: Kind

    public var id: String { "\(kind.letter):\(path)" }

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }

    /// 重命名/复制时的来源路径。
    public var sourcePath: String? {
        switch kind {
        case let .renamed(from, _), let .copied(from, _): from
        default: nil
        }
    }
}

/// 解析 `git diff-tree --name-status -z` 的输出。
public enum NameStatusParser {

    /// - Parameter output: `--name-status -z` 的原始字节。
    ///
    /// 记录之间用 NUL 分隔，**但一条记录占几个字段是不固定的**：
    ///
    ///     M\0path\0                 修改：状态 + 1 个路径
    ///     R100\0旧路径\0新路径\0      重命名：状态 + 2 个路径
    ///
    /// 按「状态、路径」交替去读的话，遇到第一个重命名之后所有条目都会错位，
    /// 后面每一个文件的状态都对不上它的路径。必须看状态字母决定读几个路径。
    public static func parse(_ output: Data) -> [CommitFileChange] {
        // 丢掉空字段。-z 的输出以 NUL 收尾，保留空串的话末尾会多出一个，
        // 而它会被截断的重命名当成"新路径"用，凭空造出一条空路径的记录。
        // 状态和路径本身都不可能为空，所以丢掉是安全的。
        let fields =
            output
            .split(separator: 0x00, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }

        var changes: [CommitFileChange] = []
        var index = 0

        while index < fields.count {
            let status = fields[index]
            guard let letter = status.first else { break }
            // R/C 后面跟的数字是相似度，例如 R100 表示内容完全一致的纯改名
            let similarity = Int(status.dropFirst()) ?? 0
            let takesTwoPaths = (letter == "R" || letter == "C")
            let needed = takesTwoPaths ? 2 : 1

            guard index + needed < fields.count else { break }

            if takesTwoPaths {
                let source = fields[index + 1]
                let destination = fields[index + 2]
                let kind: CommitFileChange.Kind =
                    letter == "R"
                    ? .renamed(from: source, similarity: similarity)
                    : .copied(from: source, similarity: similarity)
                changes.append(CommitFileChange(path: destination, kind: kind))
            } else {
                let path = fields[index + 1]
                let kind: CommitFileChange.Kind =
                    switch letter {
                    case "A": .added
                    case "M": .modified
                    case "D": .deleted
                    case "T": .typeChanged
                    default: .other(status)
                    }
                changes.append(CommitFileChange(path: path, kind: kind))
            }

            index += needed + 1
        }

        return changes
    }
}

extension GitClient {

    /// 列出某次提交改动的文件。
    ///
    /// 两个必须绕开的坑，都是实测出来的：
    ///
    /// 1. **merge 提交默认什么都不输出。** `git diff-tree <merge>` 面对多个父提交
    ///    时不知道该跟谁比，于是干脆不输出。加 `--first-parent` 也**没用**（仍然为空），
    ///    必须显式写成 `<hash>^1 <hash>` 才会跟第一个父提交比。
    ///
    /// 2. **根提交同样输出为空**，因为它没有父提交。得靠 `--root` 让它跟空树比。
    ///
    /// 用 `-z` 是项目惯例：默认输出会对含空格和中文的路径加引用转义。
    public func filesChanged(
        inCommit hash: String,
        in repository: URL,
        detectRenames: Bool = true
    ) async throws -> [CommitFileChange] {
        var arguments = ["diff-tree", "--no-commit-id", "--name-status", "-r", "-z"]
        if detectRenames {
            arguments.append("-M")
        }

        // 先按「有父提交」来问。根提交会以空输出回来，再退回 --root 重试。
        let withParent = try await runReturningResult(
            arguments + ["\(hash)^1", hash],
            in: repository,
            allowsOptionalLocks: false
        )

        if withParent.isSuccess, !withParent.standardOutput.isEmpty {
            return NameStatusParser.parse(withParent.standardOutput)
        }

        // `<hash>^1` 在根提交上会直接报错（没有那个父），所以这里是常规路径而非兜底
        let fromRoot = try await run(
            arguments + ["--root", hash],
            in: repository,
            allowsOptionalLocks: false
        )
        return NameStatusParser.parse(fromRoot.standardOutput)
    }

    /// 取某次提交里单个文件的 diff。
    ///
    /// 参数收的是 ``CommitFileChange`` 而不是一个路径字符串，因为**重命名必须
    /// 同时给出旧路径和新路径**：
    ///
    /// `-M`（重命名检测）要同时看见「旧路径被删」和「新路径被加」这一对才能配对。
    /// 只用 `-- <新路径>` 过滤的话，旧路径那条记录被过滤掉了，配不上对，
    /// git 于是把它当成一个全新文件——一次纯改名会显示成"整个文件都是新增的"，
    /// 几百行绿色，而真实改动是零。传两个路径进去才会得到 `rename from/to`。
    ///
    /// merge 和根提交的处理同 ``filesChanged(inCommit:in:detectRenames:)``：
    /// `git show <merge> -- <path>` 对合并提交同样是空输出。
    public func diff(
        ofFile change: CommitFileChange,
        inCommit hash: String,
        in repository: URL,
        contextLines: Int = 3
    ) async throws -> FileDiff {
        // 旧路径放前面，跟 git 自己输出 `diff --git a/旧 b/新` 的顺序一致
        var paths: [String] = []
        if let source = change.sourcePath {
            paths.append(source)
        }
        paths.append(change.path)

        let arguments = [
            "diff-tree", "-p", "--no-commit-id", "-M", "--unified=\(contextLines)",
        ]

        let withParent = try await runReturningResult(
            arguments + ["\(hash)^1", hash, "--"] + paths,
            in: repository,
            allowsOptionalLocks: false
        )

        if withParent.isSuccess, !withParent.standardOutput.isEmpty {
            return try DiffParser.parse(withParent.standardOutput, path: change.path)
        }

        let fromRoot = try await run(
            arguments + ["--root", hash, "--"] + paths,
            in: repository,
            allowsOptionalLocks: false
        )
        return try DiffParser.parse(fromRoot.standardOutput, path: change.path)
    }
}
