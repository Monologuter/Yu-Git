import Foundation

/// 行内差异：一对删除行 / 新增行之间，具体哪几段变了。
///
/// 整行标红标绿的问题是**信息量太低**：改了一个变量名和重写了整行，
/// 看上去一模一样。标出真正变化的那几个词，一眼就能看出改动的规模。
public enum InlineDiff {

    /// token 数超过这个值就放弃逐词比较。
    ///
    /// 逐词比较是 O(n×m) 的。正常代码一行几十个 token，随便算；
    /// 但 minified 的 JS 一行可能有几万个字符，那样会卡住整个界面。
    /// 超限时退回整行标色——那正是原来的行为，不会更糟。
    static let tokenLimit = 400

    /// 比较一对行，返回各自「变了的」字符范围。
    ///
    /// 范围是**字符（Character）索引**，不是 UTF-8 字节：
    /// 上层要拿它去切 String，用字节偏移会在中文和 emoji 上切碎。
    public static func compare(
        old: String,
        new: String
    ) -> (old: [Range<Int>], new: [Range<Int>]) {
        let oldTokens = tokenize(old)
        let newTokens = tokenize(new)

        guard oldTokens.count <= tokenLimit, newTokens.count <= tokenLimit else {
            return ([], [])
        }
        // 完全一样就没什么可标的（配对逻辑可能把两行不相干的凑一起）
        guard old != new else { return ([], []) }

        let common = longestCommonSubsequence(oldTokens, newTokens)

        return (
            changedRanges(in: oldTokens, keeping: common.map(\.oldIndex)),
            changedRanges(in: newTokens, keeping: common.map(\.newIndex))
        )
    }

    // MARK: - 分词

    /// 一个 token：一段字符及其在原串中的范围。
    struct Token: Equatable {
        let text: String
        let range: Range<Int>

        static func == (lhs: Token, rhs: Token) -> Bool { lhs.text == rhs.text }
    }

    /// 按词切分。
    ///
    /// 分词规则要同时照顾代码和中文：
    /// - 连续的字母数字下划线算一个词（`userName`、`sha256` 不该被拆开）
    /// - **中文按单字切**——中文没有空格分词，整句当一个 token 的话，
    ///   改一个字就会把整句都标成变化，等于没做行内 diff
    /// - 空白单独成词，这样缩进变化也能被看见
    /// - 其余标点各自成词
    static func tokenize(_ line: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(line)
        var index = 0

        while index < characters.count {
            let start = index
            let character = characters[index]

            if character.isWhitespace {
                while index < characters.count, characters[index].isWhitespace { index += 1 }
            } else if isWordCharacter(character) {
                while index < characters.count, isWordCharacter(characters[index]) { index += 1 }
            } else {
                // 中文、标点、emoji 都走这里，一个字符一个 token
                index += 1
            }

            tokens.append(
                Token(text: String(characters[start..<index]), range: start..<index))
        }
        return tokens
    }

    /// 属于「一个词」的字符。
    ///
    /// 刻意只认 ASCII 字母：`isLetter` 会把中文也算进来，
    /// 那样一整句中文会粘成一个 token，改一个字就整句标红。
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "_")
    }

    // MARK: - 最长公共子序列

    struct Match {
        let oldIndex: Int
        let newIndex: Int
    }

    /// 标准的 LCS 动态规划。
    ///
    /// 用 LCS 而不是"公共前缀 + 公共后缀"那种便宜做法：后者遇到
    /// 一行里改了两处（很常见，比如同时改了参数名和返回值）就会把
    /// 中间整段都标成变化，行内 diff 的意义就没了。
    static func longestCommonSubsequence(_ old: [Token], _ new: [Token]) -> [Match] {
        guard !old.isEmpty, !new.isEmpty else { return [] }

        // lengths[i][j] = old[i...] 与 new[j...] 的 LCS 长度
        var lengths = [[Int]](
            repeating: [Int](repeating: 0, count: new.count + 1), count: old.count + 1)

        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                if old[i] == new[j] {
                    lengths[i][j] = lengths[i + 1][j + 1] + 1
                } else {
                    lengths[i][j] = max(lengths[i + 1][j], lengths[i][j + 1])
                }
            }
        }

        var matches: [Match] = []
        var i = 0
        var j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                matches.append(Match(oldIndex: i, newIndex: j))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return matches
    }

    /// 把「保留下来的 token 下标」反过来算成「变化的字符范围」，相邻的合并。
    ///
    /// 合并是为了少画几个色块：`foo(bar)` 改成 `foo(baz)` 时，
    /// 变化的可能是连着的两三个 token，分开标会碎成一片。
    private static func changedRanges(in tokens: [Token], keeping kept: [Int]) -> [Range<Int>] {
        let keptSet = Set(kept)
        var ranges: [Range<Int>] = []
        var current: Range<Int>?

        for (index, token) in tokens.enumerated() {
            if keptSet.contains(index) {
                if let range = current {
                    ranges.append(range)
                    current = nil
                }
                continue
            }
            if let range = current {
                current = range.lowerBound..<token.range.upperBound
            } else {
                current = token.range
            }
        }
        if let range = current { ranges.append(range) }
        return ranges
    }
}

// MARK: - 行配对

extension DiffHunk {

    /// 把 hunk 里的删除行和新增行配成对，供行内 diff 用。
    ///
    /// 只配「一段连续的删除紧跟一段等长的连续新增」这种情况。
    /// 两段长度不等时不配：那通常意味着整块被重写了，
    /// 硬凑成对只会给出一堆看起来很随机的高亮，比整行标色更难读。
    public var inlinePairs: [(oldIndex: Int, newIndex: Int)] {
        var pairs: [(oldIndex: Int, newIndex: Int)] = []
        var index = 0

        while index < lines.count {
            guard lines[index].kind == .deletion else {
                index += 1
                continue
            }

            let deletionStart = index
            while index < lines.count, lines[index].kind == .deletion { index += 1 }
            let deletionCount = index - deletionStart

            let additionStart = index
            while index < lines.count, lines[index].kind == .addition { index += 1 }
            let additionCount = index - additionStart

            guard deletionCount == additionCount, deletionCount > 0 else { continue }
            for offset in 0..<deletionCount {
                pairs.append((deletionStart + offset, additionStart + offset))
            }
        }
        return pairs
    }
}
