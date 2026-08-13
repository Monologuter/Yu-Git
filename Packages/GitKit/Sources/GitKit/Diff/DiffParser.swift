import Foundation

/// 统一 diff 格式的解析器。
///
/// 与 ``PatchBuilder`` 是一对：解析出的结构必须能被原样还原成可 `git apply` 的 patch。
/// 这条同构关系用往返测试锁死——它是 hunk / 行级暂存不损坏用户文件的根本保证
/// （工程规范 §6 铁律 3）。
public enum DiffParser {

    /// 解析 `git diff` 对**单个文件**的输出。
    ///
    /// - Parameter path: 文件路径。不从 diff 头部解析，因为 git 会对含引号或反斜杠的
    ///   路径加引用转义，`core.quotepath=false` 只免了非 ASCII 那部分。
    public static func parse(_ data: Data, path: String) throws -> FileDiff {
        guard !data.isEmpty else {
            return FileDiff(path: path, change: .modified, hunks: [])
        }

        var change = FileDiff.Change.modified
        var isBinary = false
        var oldMode: String?
        var newMode: String?
        var hunks: [DiffHunk] = []
        var headerLines: [String] = []

        // 必须按**字节**切行，不能用 String.split(separator: "\n")。
        //
        // Swift 把 "\r\n" 当作单个 Character（grapheme cluster），它不等于 "\n"，
        // 于是 CRLF 文件的整个 diff 会被当成一行，解析结果完全错乱。
        // 按 0x0A 切分还能把行尾的 \r 原样留在内容里——CRLF 文件的行内容本就含它，
        // 少了这个字节，暂存就会把用户的换行符从 CRLF 悄悄改成 LF。
        //
        // omittingEmptySubsequences: false 保留空行，diff 里的空行是有意义的内容行。
        let lines =
            data
            .split(separator: 0x0A, omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        var index = 0

        // 先吃掉文件头（diff --git / index / mode / --- / +++ / Binary files）
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("@@") { break }
            headerLines.append(line)

            if line.hasPrefix("new file mode ") {
                change = .added
                newMode = String(line.dropFirst("new file mode ".count))
            } else if line.hasPrefix("deleted file mode ") {
                change = .deleted
                oldMode = String(line.dropFirst("deleted file mode ".count))
            } else if line.hasPrefix("old mode ") {
                oldMode = String(line.dropFirst("old mode ".count))
                change = .modeChanged
            } else if line.hasPrefix("new mode ") {
                newMode = String(line.dropFirst("new mode ".count))
            } else if line.hasPrefix("rename from ") {
                change = .renamed(from: String(line.dropFirst("rename from ".count)))
            } else if line.hasPrefix("Binary files ") || line.hasPrefix("GIT binary patch") {
                isBinary = true
            }
            index += 1
        }

        // 再逐个解析 hunk
        while index < lines.count {
            guard lines[index].hasPrefix("@@") else {
                index += 1
                continue
            }
            let (hunk, nextIndex) = try parseHunk(lines, startingAt: index)
            hunks.append(hunk)
            index = nextIndex
        }

        // 有内容变化就不是单纯的模式变更
        if case .modeChanged = change, !hunks.isEmpty {
            change = .modified
        }

        return FileDiff(
            path: path,
            change: change,
            hunks: hunks,
            isBinary: isBinary,
            oldMode: oldMode,
            newMode: newMode,
            header: headerLines.joined(separator: "\n")
        )
    }

    // MARK: - hunk

    private static func parseHunk(_ lines: [String], startingAt start: Int) throws -> (DiffHunk, Int) {
        let header = lines[start]
        let range = try parseHunkHeader(header)

        var diffLines: [DiffLine] = []
        var oldLine = range.oldStart
        var newLine = range.newStart
        var index = start + 1

        while index < lines.count {
            let line = lines[index]

            // 下一个 hunk 或下一个文件的头，本 hunk 到此为止
            if line.hasPrefix("@@") || line.hasPrefix("diff --git ") {
                break
            }

            // `\ No newline at end of file` 描述的是**上一行**，不是独立的一行内容
            if line.hasPrefix("\\") {
                if let last = diffLines.popLast() {
                    diffLines.append(
                        DiffLine(
                            kind: last.kind,
                            text: last.text,
                            oldLineNumber: last.oldLineNumber,
                            newLineNumber: last.newLineNumber,
                            isMissingNewline: true
                        )
                    )
                }
                index += 1
                continue
            }

            // git 输出的最后会多一个空串（因为内容以 \n 结尾），不是内容行
            if line.isEmpty && index == lines.count - 1 {
                index += 1
                continue
            }

            let marker = line.first
            let content = line.isEmpty ? "" : String(line.dropFirst())

            switch marker {
            case "+":
                diffLines.append(
                    DiffLine(kind: .addition, text: content, oldLineNumber: nil, newLineNumber: newLine))
                newLine += 1
            case "-":
                diffLines.append(
                    DiffLine(kind: .deletion, text: content, oldLineNumber: oldLine, newLineNumber: nil))
                oldLine += 1
            case " ", nil:
                // 空串按上下文空行处理：某些工具产出的 diff 会省掉上下文行的前导空格
                diffLines.append(
                    DiffLine(kind: .context, text: content, oldLineNumber: oldLine, newLineNumber: newLine))
                oldLine += 1
                newLine += 1
            default:
                throw GitError.parseFailure(
                    reason: "hunk 内出现无法识别的行前缀「\(marker.map(String.init) ?? "")」",
                    context: line
                )
            }
            index += 1
        }

        let hunk = DiffHunk(
            oldStart: range.oldStart,
            oldCount: range.oldCount,
            newStart: range.newStart,
            newCount: range.newCount,
            heading: range.heading,
            lines: diffLines
        )
        return (hunk, index)
    }

    /// 解析 `@@ -1,5 +1,6 @@ heading`。count 为 1 时 git 会省略，此时默认为 1。
    static func parseHunkHeader(
        _ header: String
    ) throws -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, heading: String) {
        guard header.hasPrefix("@@"),
            let closing = header.range(of: "@@", range: header.index(header.startIndex, offsetBy: 2)..<header.endIndex)
        else {
            throw GitError.parseFailure(reason: "不是合法的 hunk 头", context: header)
        }

        let rangePart = header[header.index(header.startIndex, offsetBy: 2)..<closing.lowerBound]
            .trimmingCharacters(in: .whitespaces)
        let heading = String(header[closing.upperBound...]).trimmingCharacters(in: .whitespaces)

        let parts = rangePart.split(separator: " ")
        guard parts.count == 2,
            parts[0].hasPrefix("-"), parts[1].hasPrefix("+"),
            let old = parseRange(parts[0].dropFirst()),
            let new = parseRange(parts[1].dropFirst())
        else {
            throw GitError.parseFailure(reason: "无法解析 hunk 范围", context: header)
        }

        return (old.start, old.count, new.start, new.count, heading)
    }

    private static func parseRange(_ text: Substring) -> (start: Int, count: Int)? {
        let parts = text.split(separator: ",")
        guard let start = Int(parts[0]) else { return nil }
        if parts.count == 1 {
            return (start, 1)
        }
        guard parts.count == 2, let count = Int(parts[1]) else { return nil }
        return (start, count)
    }
}
