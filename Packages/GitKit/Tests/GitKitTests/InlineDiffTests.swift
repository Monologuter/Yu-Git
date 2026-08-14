import Foundation
import Testing

@testable import GitKit

@Suite("行内差异")
struct InlineDiffTests {

    /// 把变化的范围用 「」 标出来，方便一眼看出标对了没有。
    private func mark(_ line: String, _ ranges: [Range<Int>]) -> String {
        let characters = Array(line)
        var result = ""
        var cursor = 0
        for range in ranges {
            result += String(characters[cursor..<range.lowerBound])
            result += "「" + String(characters[range]) + "」"
            cursor = range.upperBound
        }
        result += String(characters[cursor...])
        return result
    }

    private func compare(_ old: String, _ new: String) -> (old: String, new: String) {
        let result = InlineDiff.compare(old: old, new: new)
        return (mark(old, result.old), mark(new, result.new))
    }

    // MARK: - 基本情形

    @Test("只改一个词，只标那个词")
    func marksSingleChangedWord() {
        let result = compare("let count = 1", "let total = 1")
        #expect(result.old == "let 「count」 = 1")
        #expect(result.new == "let 「total」 = 1")
    }

    @Test("一行里改了两处，两处都标出来")
    func marksTwoSeparateChanges() {
        // 这正是"公共前缀 + 公共后缀"那种便宜做法会失败的地方：
        // 它只能给出一个从第一处到最后一处的大范围，把中间没变的也圈进去
        let result = compare("func run(a: Int) -> Bool", "func run(b: Int) -> String")
        #expect(result.old == "func run(「a」: Int) -> 「Bool」")
        #expect(result.new == "func run(「b」: Int) -> 「String」")
    }

    @Test("纯新增的部分只在新行标出")
    func marksInsertionOnly() {
        let result = compare("call(a)", "call(a, b)")
        #expect(result.old == "call(a)")
        #expect(result.new == "call(a「, b」)")
    }

    @Test("完全相同的两行不标任何东西")
    func identicalLinesHaveNoMarks() {
        let result = InlineDiff.compare(old: "same", new: "same")
        #expect(result.old.isEmpty)
        #expect(result.new.isEmpty)
    }

    // MARK: - 中文

    @Test("中文按单字比较，改一个字不会整句标红")
    func chineseComparesByCharacter() {
        // 中文没有空格分词。整句当一个 token 的话，改一个字整句都会被标成变化，
        // 行内 diff 就等于没做
        let result = compare("提交信息生成失败", "提交信息生成成功")
        #expect(result.old == "提交信息生成「失败」")
        #expect(result.new == "提交信息生成「成功」")
    }

    @Test("中英混排")
    func mixedChineseAndEnglish() {
        let result = compare(#"print("你好")"#, #"print("再见")"#)
        #expect(result.old == #"print("「你好」")"#)
        #expect(result.new == #"print("「再见」")"#)
    }

    // MARK: - 分词规则

    @Test("标识符不会被拆开")
    func keepsIdentifiersWhole() {
        // sha256 拆成 sha + 256 的话，改成 sha512 会只标 512，
        // 而实际上整个标识符都变了
        let tokens = InlineDiff.tokenize("let sha256 = x")
        #expect(tokens.map(\.text) == ["let", " ", "sha256", " ", "=", " ", "x"])
    }

    @Test("空白单独成词，缩进变化能被看见")
    func whitespaceIsItsOwnToken() {
        let result = compare("  a", "    a")
        #expect(result.old.contains("「"))
    }

    @Test("中文逐字成词")
    func chineseSplitsPerCharacter() {
        #expect(InlineDiff.tokenize("你好").map(\.text) == ["你", "好"])
    }

    // MARK: - 边界

    @Test("超长的行放弃逐词比较，退回整行标色")
    func givesUpOnVeryLongLines() {
        // 逐词比较是 O(n×m)。minified 的 JS 一行几万字符，
        // 真去算会把界面卡住——退回整行标色正是原来的行为，不会更糟
        let long = String(repeating: "a b ", count: InlineDiff.tokenLimit)
        let result = InlineDiff.compare(old: long, new: long + "c")
        #expect(result.old.isEmpty)
        #expect(result.new.isEmpty)
    }

    @Test("空行不炸")
    func handlesEmptyLines() {
        let result = InlineDiff.compare(old: "", new: "新增")
        #expect(result.old.isEmpty)
        #expect(!result.new.isEmpty)
    }

    @Test("范围有序、不重叠、不越界")
    func rangesAreWellFormed() {
        let old = "let a = foo(bar, baz)"
        let new = "let b = foo(qux, baz)"
        let result = InlineDiff.compare(old: old, new: new)

        for (previous, next) in zip(result.old, result.old.dropFirst()) {
            #expect(previous.upperBound <= next.lowerBound)
        }
        for range in result.old {
            #expect(range.lowerBound >= 0)
            #expect(range.upperBound <= Array(old).count)
        }
        for range in result.new {
            #expect(range.upperBound <= Array(new).count)
        }
    }

    // MARK: - 行配对

    @Test("等长的删除块与新增块一一配对")
    func pairsEqualSizedBlocks() {
        let hunk = DiffHunk(
            oldStart: 1, oldCount: 2, newStart: 1, newCount: 2, heading: "",
            lines: [
                DiffLine(kind: .context, text: "前", oldLineNumber: 1, newLineNumber: 1),
                DiffLine(kind: .deletion, text: "旧1", oldLineNumber: 2, newLineNumber: nil),
                DiffLine(kind: .deletion, text: "旧2", oldLineNumber: 3, newLineNumber: nil),
                DiffLine(kind: .addition, text: "新1", oldLineNumber: nil, newLineNumber: 2),
                DiffLine(kind: .addition, text: "新2", oldLineNumber: nil, newLineNumber: 3),
            ])

        let pairs = hunk.inlinePairs
        #expect(pairs.count == 2)
        #expect(pairs[0] == (1, 3))
        #expect(pairs[1] == (2, 4))
    }

    @Test("长度不等的块不配对")
    func doesNotPairUnevenBlocks() {
        // 一删三增通常是整块重写，硬凑成对只会给出一堆看起来很随机的高亮，
        // 比整行标色更难读
        let hunk = DiffHunk(
            oldStart: 1, oldCount: 1, newStart: 1, newCount: 3, heading: "",
            lines: [
                DiffLine(kind: .deletion, text: "旧", oldLineNumber: 1, newLineNumber: nil),
                DiffLine(kind: .addition, text: "新1", oldLineNumber: nil, newLineNumber: 1),
                DiffLine(kind: .addition, text: "新2", oldLineNumber: nil, newLineNumber: 2),
                DiffLine(kind: .addition, text: "新3", oldLineNumber: nil, newLineNumber: 3),
            ])
        #expect(hunk.inlinePairs.isEmpty)
    }

    @Test("只有删除没有新增时不配对")
    func doesNotPairPureDeletion() {
        let hunk = DiffHunk(
            oldStart: 1, oldCount: 1, newStart: 1, newCount: 0, heading: "",
            lines: [
                DiffLine(kind: .deletion, text: "没了", oldLineNumber: 1, newLineNumber: nil)
            ])
        #expect(hunk.inlinePairs.isEmpty)
    }
}
