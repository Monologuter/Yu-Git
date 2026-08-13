import Foundation

/// 一个冲突块。
public struct ConflictBlock: Sendable, Equatable, Identifiable {

    /// 在文件里的序号（0 起）。用它定位，不用内容——内容会被改。
    public let id: Int

    /// `<<<<<<<` 后面那个标签，通常是 `HEAD` 或 `ours`。
    public let oursLabel: String
    /// `>>>>>>>` 后面那个标签，通常是分支名或 `theirs`。
    public let theirsLabel: String

    public let ours: [String]
    /// 共同祖先的内容。
    ///
    /// 只有 `diff3` / `zdiff3` 冲突风格才有。**没有它就没法判断双方各自改了什么**——
    /// 只能看到两个不同的结果，无从知道谁动了哪部分。所以读冲突前会先用
    /// `git checkout --conflict=diff3` 把它补出来。
    public let base: [String]?
    public let theirs: [String]

    public init(
        id: Int,
        oursLabel: String,
        theirsLabel: String,
        ours: [String],
        base: [String]?,
        theirs: [String]
    ) {
        self.id = id
        self.oursLabel = oursLabel
        self.theirsLabel = theirsLabel
        self.ours = ours
        self.base = base
        self.theirs = theirs
    }

    /// 双方内容一样——git 偶尔会因为上下文对不齐造出这种块，一键取任意一边即可。
    public var isTrivial: Bool { ours == theirs }
}

/// 一个带冲突的文件。
public struct ConflictedFile: Sendable, Equatable {

    public enum Segment: Sendable, Equatable {
        /// 没有冲突的原样内容。
        case text([String])
        case conflict(ConflictBlock)
    }

    public let path: String
    public let segments: [Segment]
    /// 原文件是否以换行结尾。重新拼装时要还原，否则会给文件凭空加/减一个换行。
    public let hasTrailingNewline: Bool
    /// 文件用的是 CRLF。重新生成冲突标记行时要跟着补 CR，
    /// 否则会在一份 CRLF 文件里混进几行 LF。
    public let usesCRLF: Bool

    public var blocks: [ConflictBlock] {
        segments.compactMap { if case let .conflict(block) = $0 { block } else { nil } }
    }

    public var hasConflicts: Bool { !blocks.isEmpty }

    public init(
        path: String,
        segments: [Segment],
        hasTrailingNewline: Bool,
        usesCRLF: Bool = false
    ) {
        self.path = path
        self.segments = segments
        self.hasTrailingNewline = hasTrailingNewline
        self.usesCRLF = usesCRLF
    }
}

/// 解析工作区里带冲突标记的文件。
public enum ConflictParser {

    /// git 的冲突标记固定是 7 个字符。
    static let markerLength = 7

    /// 解析文件内容。
    ///
    /// 按字节切行（而不是 `String.split`）：Swift 把 `"\r\n"` 当作一个 Character，
    /// 按 `"\n"` 切根本切不开 CRLF 文件——而 Windows 上写的代码里全是 CRLF。
    /// 切完保留每行原本的行尾，重新拼装时一字不差。
    public static func parse(_ data: Data, path: String) -> ConflictedFile {
        let lines = splitLines(data)
        let hasTrailingNewline = data.last == 0x0A

        var segments: [ConflictedFile.Segment] = []
        var plain: [String] = []
        var blockID = 0
        var index = 0

        func flushPlain() {
            guard !plain.isEmpty else { return }
            segments.append(.text(plain))
            plain.removeAll()
        }

        while index < lines.count {
            guard let oursLabel = marker(lines[index], prefix: "<") else {
                plain.append(lines[index])
                index += 1
                continue
            }

            // 找齐这一块的三个（或四个）分界。任何一个缺失都说明标记不成对——
            // 那多半是文件里本来就写着这样的内容（比如一份讲冲突的文档），
            // 当普通文本处理，不要硬当成冲突块。
            var separatorIndex: Int?
            var baseIndex: Int?
            var endIndex: Int?

            var scan = index + 1
            while scan < lines.count {
                if marker(lines[scan], prefix: "<") != nil {
                    // 嵌套的开始标记：上一块没有收尾，放弃
                    break
                }
                if baseIndex == nil, separatorIndex == nil, marker(lines[scan], prefix: "|") != nil {
                    baseIndex = scan
                } else if separatorIndex == nil, marker(lines[scan], prefix: "=") != nil {
                    separatorIndex = scan
                } else if marker(lines[scan], prefix: ">") != nil {
                    endIndex = scan
                    break
                }
                scan += 1
            }

            guard
                let separator = separatorIndex,
                let end = endIndex,
                let theirsLabel = marker(lines[end], prefix: ">")
            else {
                plain.append(lines[index])
                index += 1
                continue
            }

            flushPlain()

            let oursEnd = baseIndex ?? separator
            let block = ConflictBlock(
                id: blockID,
                oursLabel: oursLabel,
                theirsLabel: theirsLabel,
                ours: Array(lines[(index + 1)..<oursEnd]),
                base: baseIndex.map { Array(lines[($0 + 1)..<separator]) },
                theirs: Array(lines[(separator + 1)..<end])
            )
            segments.append(.conflict(block))
            blockID += 1
            index = end + 1
        }

        flushPlain()

        return ConflictedFile(
            path: path,
            segments: segments,
            hasTrailingNewline: hasTrailingNewline,
            usesCRLF: lines.contains { $0.hasSuffix("\r") }
        )
    }

    /// 把选定的解决方案填回去，拼出完整文件内容。
    ///
    /// - Parameter resolutions: 块 id → 该块最终的内容行。缺席的块保持冲突原样，
    ///   这样可以一块一块地解，中途保存也不会丢掉还没处理的块。
    public static func render(
        _ file: ConflictedFile,
        resolutions: [Int: [String]]
    ) -> String {
        var lines: [String] = []
        let eol = file.usesCRLF ? "\r" : ""

        func marker(_ character: Character, label: String) -> String {
            let head = String(repeating: character, count: markerLength)
            return label.isEmpty ? head + eol : "\(head) \(label)\(eol)"
        }

        for segment in file.segments {
            switch segment {
            case let .text(text):
                lines += text
            case let .conflict(block):
                if let resolved = resolutions[block.id] {
                    lines += resolved
                } else {
                    // 还没解决的块原样写回，连标记一起
                    lines.append(marker("<", label: block.oursLabel))
                    lines += block.ours
                    if let base = block.base {
                        lines.append(marker("|", label: "base"))
                        lines += base
                    }
                    lines.append(marker("=", label: ""))
                    lines += block.theirs
                    lines.append(marker(">", label: block.theirsLabel))
                }
            }
        }

        let text = lines.joined(separator: "\n")
        return file.hasTrailingNewline && !text.isEmpty ? text + "\n" : text
    }

    // MARK: - 内部

    /// 认出一行是不是某种冲突标记，是的话返回它后面的标签。
    ///
    /// 要求恰好 7 个标记字符后跟空格或行尾。八个 `=` 是分隔线不是标记，
    /// 六个也不是——这个精确匹配让 Markdown 文档里的 `=======` 分隔线不至于被误认。
    static func marker(_ line: String, prefix: Character) -> String? {
        var characters = Array(line)
        // 行尾的 CR 是行结束符的一半，不属于标签。不先摘掉的话，CRLF 文件里
        // 的 `=======\r` 会因为「第 8 个字符不是空格」而整个不被识别。
        if characters.last == "\r" { characters.removeLast() }

        guard characters.count >= markerLength else { return nil }
        guard characters[0..<markerLength].allSatisfy({ $0 == prefix }) else { return nil }

        if characters.count == markerLength { return "" }
        guard characters[markerLength] == " " else { return nil }

        return String(characters[(markerLength + 1)...])
    }

    /// 按字节切行，保留 CR。
    static func splitLines(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }

        var lines: [String] = []
        var start = data.startIndex

        for index in data.indices where data[index] == 0x0A {
            lines.append(String(decoding: data[start..<index], as: UTF8.self))
            start = data.index(after: index)
        }

        // 末尾没有换行时最后一段也是一行
        if start < data.endIndex {
            lines.append(String(decoding: data[start...], as: UTF8.self))
        }

        return lines
    }
}
