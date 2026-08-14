import Foundation

/// 一段被识别出来的词法单元。
public struct SyntaxToken: Sendable, Equatable {

    public enum Kind: Sendable, Equatable {
        case keyword
        case string
        case comment
        case number
        /// 大写开头的标识符。不做真正的类型推断，只是个很有用的近似：
        /// 绝大多数语言的类型名都是大写开头，认对的远多于认错的。
        case type
        case plain
    }

    /// 在**字符**（Character）序列里的范围，不是 UTF-8 字节。
    /// 上层要拿它去切 String，用字节偏移会在中文和 emoji 上切碎。
    public let range: Range<Int>
    public let kind: Kind

    public init(range: Range<Int>, kind: Kind) {
        self.range = range
        self.kind = kind
    }
}

/// 逐行的词法扫描器。
///
/// **只处理单行，不跨行**。这不是偷懒，是 diff 的性质决定的：
/// 一个 hunk 给出的就是文件中间的若干行，上一行是什么、块注释在哪里开始的，
/// 信息本来就不在手上。硬要维护跨行状态，只会在 hunk 边界上给出
/// 一本正经的错误结果——而"某行的块注释没上色"比"整段代码被误当成注释"轻得多。
public enum SyntaxHighlighter {

    /// 扫描一行，返回**非纯文本**的片段。
    ///
    /// 只返回有颜色的部分，纯文本不返回：diff 里大部分字符都是纯文本，
    /// 为它们也造 token 会让结果数量翻好几倍，而上层要做的正是
    /// "把有颜色的挑出来，其余照原样画"。
    public static func tokenize(_ line: String, language: Language) -> [SyntaxToken] {
        guard language != .plain else { return [] }

        let characters = Array(line)
        guard !characters.isEmpty else { return [] }

        var tokens: [SyntaxToken] = []
        var index = 0

        while index < characters.count {
            let character = characters[index]

            // 1. 注释吃到行尾，后面什么都不用再看了
            if let length = commentMarkerLength(at: index, in: characters, language: language) {
                tokens.append(SyntaxToken(range: index..<characters.count, kind: .comment))
                _ = length
                break
            }

            // 2. 块注释。跨行的那半截认不出来，能认出同一行内闭合的就够
            if let block = language.blockComment,
                matches(block.open, at: index, in: characters)
            {
                let end = findBlockCommentEnd(
                    from: index + block.open.count, in: characters, close: block.close)
                tokens.append(SyntaxToken(range: index..<end, kind: .comment))
                index = end
                continue
            }

            // 3. 字符串
            if language.stringDelimiters.contains(character) {
                let end = findStringEnd(
                    from: index, in: characters,
                    delimiter: character, escape: language.escapeCharacter)
                tokens.append(SyntaxToken(range: index..<end, kind: .string))
                index = end
                continue
            }

            // 4. 数字。前一个字符是标识符的一部分时不算——
            //    否则 `utf8` 里的 `8`、`sha256` 里的 `256` 都会被单独染色
            //
            // 注意 `end` 从 index + 1 起步，不是 index。
            // 见下面标识符分支的注释：那是防死循环的关键。
            if character.isNumber, !isIdentifierCharacter(characters, at: index - 1) {
                var end = index + 1
                while end < characters.count, isNumberCharacter(characters[end]) {
                    end += 1
                }
                tokens.append(SyntaxToken(range: index..<end, kind: .number))
                index = end
                continue
            }

            // 5. 标识符：可能是关键字、类型名，或者什么都不是
            if isIdentifierStart(character) {
                // **`end` 必须从 index + 1 起步。**
                //
                // 从 index 起步的话，只要「能当开头」的字符集比「能当后续」的大，
                // 内层循环就会一次都不执行，`end` 停在 index，外层 `index = end`
                // 原地不动——**死循环，主线程 100% CPU，整个 app 挂起**。
                //
                // 这不是假想：`@` 能当开头（ObjC 的 @interface），却不能当后续，
                // 于是任何含 `@` 的行都会挂死。而 Vue 模板里 `@click`、`@input`
                // 满地都是，随手点开一个 .vue 文件就中招。
                //
                // 起始字符外层已经判定过属于标识符，直接跳过它，
                // 既正确又让「index 严格递增」成为结构上的保证，
                // 而不是依赖两个字符集合恰好对齐。
                var end = index + 1
                while end < characters.count, isIdentifierCharacter(characters, at: end) {
                    end += 1
                }
                let word = String(characters[index..<end])

                if language.keywords.contains(word) {
                    tokens.append(SyntaxToken(range: index..<end, kind: .keyword))
                } else if let first = word.first, first.isUppercase {
                    tokens.append(SyntaxToken(range: index..<end, kind: .type))
                }
                index = end
                continue
            }

            index += 1
        }

        return tokens
    }

    // MARK: - 扫描细节

    private static func commentMarkerLength(
        at index: Int, in characters: [Character], language: Language
    ) -> Int? {
        for marker in language.lineCommentMarkers where matches(marker, at: index, in: characters) {
            return marker.count
        }
        return nil
    }

    private static func matches(_ text: String, at index: Int, in characters: [Character]) -> Bool {
        let needle = Array(text)
        guard index + needle.count <= characters.count else { return false }
        for offset in 0..<needle.count where characters[index + offset] != needle[offset] {
            return false
        }
        return true
    }

    /// 找块注释的结束位置；同一行内没闭合就算到行尾。
    private static func findBlockCommentEnd(
        from start: Int, in characters: [Character], close: String
    ) -> Int {
        var index = start
        let needle = Array(close)
        while index < characters.count {
            if matches(close, at: index, in: characters) {
                return index + needle.count
            }
            index += 1
        }
        return characters.count
    }

    /// 找字符串的收尾引号。
    ///
    /// 没有收尾引号时算到行尾——那通常意味着这是个多行字符串的开头，
    /// 而我们只有这一行。把剩下的都当字符串，比当成代码乱染一通要好。
    private static func findStringEnd(
        from start: Int, in characters: [Character], delimiter: Character, escape: Character?
    ) -> Int {
        var index = start + 1
        while index < characters.count {
            let character = characters[index]
            if let escape, character == escape {
                // 跳过被转义的那个字符，它不可能是收尾引号
                index += 2
                continue
            }
            if character == delimiter {
                return index + 1
            }
            index += 1
        }
        return characters.count
    }

    // MARK: - 字符分类

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "@" || character == "$"
    }

    private static func isIdentifierCharacter(_ characters: [Character], at index: Int) -> Bool {
        guard index >= 0, index < characters.count else { return false }
        let character = characters[index]
        return character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private static func isNumberCharacter(_ character: Character) -> Bool {
        // 一并吃掉 0x1f、1_000_000、3.14、1e-5 里的字符。
        // 认得宽一点没关系：数字后面紧跟字母的情况已经被上面的
        // "前一个字符是标识符" 判断挡掉了。
        character.isHexDigit || character == "." || character == "_"
            || character == "x" || character == "b" || character == "o"
    }
}
