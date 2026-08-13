import Foundation

/// 一行代码的出处。
public struct BlameLine: Sendable, Equatable, Identifiable {

    public var id: Int { finalLineNumber }

    /// 引入这一行的 commit。
    public let commit: String
    /// 在当前文件里的行号（1 起）。
    public let finalLineNumber: Int
    /// 在那个 commit 的文件里的行号。
    public let originalLineNumber: Int
    public let content: String

    public init(commit: String, finalLineNumber: Int, originalLineNumber: Int, content: String) {
        self.commit = commit
        self.finalLineNumber = finalLineNumber
        self.originalLineNumber = originalLineNumber
        self.content = content
    }
}

/// blame 里出现过的一个 commit 的元数据。
public struct BlameCommit: Sendable, Equatable, Identifiable {

    public var id: String { hash }

    public let hash: String
    public let authorName: String
    public let authorEmail: String
    public let authorDate: Date
    /// 提交标题。**完整 message 不在 blame 输出里**，要单独取。
    public let summary: String

    public init(
        hash: String,
        authorName: String,
        authorEmail: String,
        authorDate: Date,
        summary: String
    ) {
        self.hash = hash
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.summary = summary
    }
}

/// 一行代码是谁写的。
public enum Authorship: Sendable, Equatable {

    /// 人写的。
    case human
    /// AI 参与的，附上识别出来的工具名。
    case ai(tool: String)

    public var isAI: Bool {
        if case .ai = self { true } else { false }
    }

    public var displayName: String {
        switch self {
        case .human: "人工"
        case let .ai(tool): tool
        }
    }
}

/// 一次 blame 的完整结果。
public struct BlameResult: Sendable, Equatable {

    public let path: String
    public let lines: [BlameLine]
    /// 出现过的所有 commit，按 hash 索引。
    public let commits: [String: BlameCommit]
    /// 每个 commit 的归属判定。
    public let authorship: [String: Authorship]

    public init(
        path: String,
        lines: [BlameLine],
        commits: [String: BlameCommit],
        authorship: [String: Authorship]
    ) {
        self.path = path
        self.lines = lines
        self.commits = commits
        self.authorship = authorship
    }

    public func authorship(ofLine line: BlameLine) -> Authorship {
        authorship[line.commit] ?? .human
    }

    /// AI 参与的行数。
    public var aiLineCount: Int {
        lines.count { authorship(ofLine: $0).isAI }
    }

    /// AI 参与的行占比（0…1）。
    public var aiRatio: Double {
        guard !lines.isEmpty else { return 0 }
        return Double(aiLineCount) / Double(lines.count)
    }

    /// 按工具分组的行数，多的在前。
    public var breakdown: [(tool: String, lineCount: Int)] {
        var counts: [String: Int] = [:]
        for line in lines {
            counts[authorship(ofLine: line).displayName, default: 0] += 1
        }
        return
            counts
            .map { (tool: $0.key, lineCount: $0.value) }
            .sorted { ($0.lineCount, $1.tool) > ($1.lineCount, $0.tool) }
    }
}

/// 从提交信息里认出 AI 的参与。
///
/// 依据是各家工具往提交信息里写的 trailer。这个清单必然会过时——工具在变，
/// 写法也在变——所以认不出时一律算人工，宁可少报也不错报：把人写的代码
/// 标成 AI 生成，比漏标更让人恼火。
public enum AuthorshipDetector {

    /// 工具标识 → 显示名。匹配时大小写不敏感。
    ///
    /// git 的 trailer 惯例是 `Co-authored-by`，但实际工具里 `Co-Authored-By`
    /// 更常见，所以只匹配值那一半，不匹配键的大小写。
    static let signatures: [(pattern: String, tool: String)] = [
        ("claude", "Claude"),
        ("anthropic", "Claude"),
        ("github copilot", "Copilot"),
        ("copilot@", "Copilot"),
        ("cursor", "Cursor"),
        ("aider", "Aider"),
        ("codeium", "Codeium"),
        ("windsurf", "Windsurf"),
        ("devin", "Devin"),
        ("gemini code assist", "Gemini"),
    ]

    /// 判断一条提交信息是否有 AI 参与。
    ///
    /// 只看**署名类的行**（`Co-authored-by:`、`Signed-off-by:`、`Generated with`），
    /// 不搜全文——正文里提到「让 Claude 看了一下」的提交是人写的，
    /// 搜全文会把它错标成 AI 生成。
    public static func detect(message: String) -> Authorship {
        for line in message.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()

            let isAttributionLine =
                trimmed.hasPrefix("co-authored-by:")
                || trimmed.hasPrefix("co-committed-by:")
                || trimmed.hasPrefix("signed-off-by:")
                || trimmed.contains("generated with")
                || trimmed.hasPrefix("assisted-by:")

            guard isAttributionLine else { continue }

            for signature in signatures where trimmed.contains(signature.pattern) {
                return .ai(tool: signature.tool)
            }
        }

        return .human
    }
}

/// 解析 `git blame --porcelain`。
public enum BlameParser {

    /// 解析输出。
    ///
    /// porcelain 的关键特性：**同一个 commit 第二次出现时，元数据行全部省略**，
    /// 只有一行 `<sha> <orig> <final>`。所以必须一路缓存已见过的 commit，
    /// 否则第二行开始的作者信息就全丢了。
    public static func parse(_ data: Data, path: String) -> (lines: [BlameLine], commits: [String: BlameCommit]) {
        // 按字节切行：blame 的内容行原样带着文件里的字节，可能是任意编码残片
        let rawLines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }

        var lines: [BlameLine] = []
        var commits: [String: BlameCommit] = [:]

        var currentHash: String?
        var currentFinal = 0
        var currentOriginal = 0
        var pending: [String: String] = [:]

        for raw in rawLines {
            // 内容行以 TAB 开头，是这一组的收尾
            if raw.hasPrefix("\t") {
                guard let hash = currentHash else { continue }

                if commits[hash] == nil, let summary = pending["summary"] {
                    commits[hash] = BlameCommit(
                        hash: hash,
                        authorName: pending["author"] ?? "",
                        authorEmail: (pending["author-mail"] ?? "")
                            .trimmingCharacters(in: CharacterSet(charactersIn: "<>")),
                        authorDate: Date(
                            timeIntervalSince1970: Double(pending["author-time"] ?? "0") ?? 0),
                        summary: summary
                    )
                }

                lines.append(
                    BlameLine(
                        commit: hash,
                        finalLineNumber: currentFinal,
                        originalLineNumber: currentOriginal,
                        content: String(raw.dropFirst())
                    ))

                pending.removeAll()
                currentHash = nil
                continue
            }

            // 组头：`<40 位 sha> <原行号> <当前行号> [<行数>]`
            if let header = parseHeader(raw) {
                currentHash = header.hash
                currentOriginal = header.original
                currentFinal = header.final
                continue
            }

            // 元数据行：`key value`
            guard currentHash != nil else { continue }
            if let space = raw.firstIndex(of: " ") {
                pending[String(raw[raw.startIndex..<space])] = String(raw[raw.index(after: space)...])
            } else if !raw.isEmpty {
                pending[raw] = ""
            }
        }

        return (lines, commits)
    }

    private static func parseHeader(_ line: String) -> (hash: String, original: Int, final: Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3 else { return nil }

        let hash = String(parts[0])
        // sha 是 40 位十六进制。不校验的话，元数据行里凑巧有三段的也会被当成组头
        guard hash.count == 40, hash.allSatisfy(\.isHexDigit) else { return nil }
        guard let original = Int(parts[1]), let final = Int(parts[2]) else { return nil }

        return (hash, original, final)
    }
}
