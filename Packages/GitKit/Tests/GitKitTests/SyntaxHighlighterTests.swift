import Foundation
import Testing

@testable import GitKit

@Suite("语法高亮")
struct SyntaxHighlighterTests {

    /// 把一行按 token 切开，渲染成 `关键字[let] 字符串["a"]` 这样便于断言的形式。
    private func render(_ line: String, _ language: Language) -> String {
        let tokens = SyntaxHighlighter.tokenize(line, language: language)
        let characters = Array(line)
        return tokens.map { token in
            let text = String(characters[token.range])
            return "\(label(token.kind))[\(text)]"
        }.joined(separator: " ")
    }

    private func label(_ kind: SyntaxToken.Kind) -> String {
        switch kind {
        case .keyword: "关键字"
        case .string: "字符串"
        case .comment: "注释"
        case .number: "数字"
        case .type: "类型"
        case .plain: "文本"
        }
    }

    // MARK: - 基本词法

    @Test("Swift 的关键字、类型、字符串")
    func highlightsSwiftBasics() {
        #expect(
            render(#"let name: String = "驭Git""#, .swift)
                == #"关键字[let] 类型[String] 字符串["驭Git"]"#)
    }

    @Test("行注释吃到行尾，里面的关键字不再单独染色")
    func lineCommentConsumesRest() {
        // 注释里出现 let、func 是常事，再把它们当关键字染一遍会很花
        #expect(render("let a = 1 // let func class", .swift) == "关键字[let] 数字[1] 注释[// let func class]")
    }

    @Test("字符串里的关键字不算关键字")
    func keywordsInsideStringsAreNotKeywords() {
        #expect(render(#""func class let""#, .swift) == #"字符串["func class let"]"#)
    }

    @Test("转义引号不会提前结束字符串")
    func escapedQuoteDoesNotEndString() {
        // 少了转义处理的话，字符串会在 \" 处断开，后半截被当成代码乱染
        #expect(render(#""说\"引用\"的话""#, .swift) == #"字符串["说\"引用\"的话"]"#)
    }

    @Test("同一行内闭合的块注释")
    func inlineBlockComment() {
        #expect(render("let /* 中间 */ a", .swift) == "关键字[let] 注释[/* 中间 */]")
    }

    @Test("没闭合的块注释算到行尾，而不是吞掉后面所有行")
    func unterminatedBlockCommentStopsAtLineEnd() {
        // 逐行扫描拿不到下一行，只能到此为止。
        // 这正是"宁可少染色也不要染错一大片"的取舍。
        #expect(render("code /* 开头", .swift) == "注释[/* 开头]")
    }

    // MARK: - 数字

    @Test("标识符里的数字不单独染色")
    func digitsInsideIdentifiersAreNotNumbers() {
        // 少了这条判断，utf8 的 8、sha256 的 256 都会被挑出来染成数字，
        // 一行代码上散着几块杂色，比不上色还难读
        #expect(render("let utf8 = sha256", .swift) == "关键字[let]")
    }

    @Test("十六进制、下划线分组、小数都当作一个数字")
    func recognizesNumberForms() {
        #expect(render("0xFF", .swift) == "数字[0xFF]")
        #expect(render("1_000_000", .swift) == "数字[1_000_000]")
        #expect(render("3.14", .swift) == "数字[3.14]")
    }

    // MARK: - 多语言

    @Test("Python 用 # 注释")
    func pythonComments() {
        #expect(render("def f(): # 说明", .python) == "关键字[def] 注释[# 说明]")
    }

    @Test("JS 的模板字符串")
    func javascriptTemplateString() {
        #expect(render("const x = `模板`", .javascript) == "关键字[const] 字符串[`模板`]")
    }

    @Test("Go 的反引号原始字符串")
    func goRawString() {
        #expect(render("var s = `raw`", .go) == "关键字[var] 字符串[`raw`]")
    }

    @Test("Python 没有块注释，/* 只是普通字符")
    func languageWithoutBlockComments() {
        #expect(render("a /* b", .python) == "")
    }

    // MARK: - 语言识别

    @Test("按扩展名识别")
    func detectsByExtension() {
        #expect(Language.detect(fromPath: "a/b/Main.swift") == .swift)
        #expect(Language.detect(fromPath: "src/index.tsx") == .javascript)
        #expect(Language.detect(fromPath: "scripts/deploy.sh") == .shell)
        #expect(Language.detect(fromPath: "conf/app.yaml") == .yaml)
        #expect(Language.detect(fromPath: "readme.md") == .plain)
    }

    @Test("没有扩展名的文件靠文件名认")
    func detectsByFilename() {
        #expect(Language.detect(fromPath: "Dockerfile") == .shell)
        #expect(Language.detect(fromPath: "some/path/Makefile") == .shell)
    }

    @Test("认不出的语言不产生任何 token")
    func plainLanguageProducesNothing() {
        #expect(SyntaxHighlighter.tokenize("let func class", language: .plain).isEmpty)
    }

    // MARK: - 健壮性

    @Test("中文和 emoji 不会把范围切错")
    func handlesMultibyteCharacters() {
        // 范围是按 Character 算的。用 UTF-8 字节偏移的话，
        // 这里切出来的会是半个字，上层拿去截 String 会崩或乱码。
        let line = #"let 说明 = "🎉 完成""#
        let tokens = SyntaxHighlighter.tokenize(line, language: .swift)
        let characters = Array(line)
        for token in tokens {
            #expect(token.range.lowerBound >= 0)
            #expect(token.range.upperBound <= characters.count)
        }
        #expect(render(line, .swift) == #"关键字[let] 字符串["🎉 完成"]"#)
    }

    @Test("空行和纯空白不炸")
    func handlesEmptyInput() {
        #expect(SyntaxHighlighter.tokenize("", language: .swift).isEmpty)
        #expect(SyntaxHighlighter.tokenize("    ", language: .swift).isEmpty)
    }

    // MARK: - 终止性
    //
    // 这一组防的是**挂起**，不是染错色。扫描器的外层是
    // `while index < count`，任何一个分支忘了让 index 前进，
    // 整个 app 就会卡死在一行文本上——比颜色不对严重得多。

    @Test("@ 开头的标识符不会死循环", .timeLimit(.minutes(1)))
    func doesNotHangOnAtSign() {
        // 真实事故：@ 能当标识符开头（ObjC 的 @interface），却不在「能当后续」
        // 的字符集里，于是内层循环一次都不执行，index 原地踏步。
        // Vue 模板里 @click 满地都是，随手点开一个 .vue 文件就挂。
        _ = SyntaxHighlighter.tokenize(#"<div @click="run" @input="x" />"#, language: .javascript)
        _ = SyntaxHighlighter.tokenize("@interface Foo", language: .cLike)
        _ = SyntaxHighlighter.tokenize("@", language: .swift)
        _ = SyntaxHighlighter.tokenize("@@@@", language: .swift)
    }

    @Test("非 ASCII 数字不会死循环", .timeLimit(.minutes(1)))
    func doesNotHangOnUnicodeDigits() {
        // 全角数字、罗马数字、上标的 isNumber 都为真，但 isHexDigit 为假——
        // 数字分支同样会一次都不前进
        _ = SyntaxHighlighter.tokenize("步骤１２３", language: .swift)
        _ = SyntaxHighlighter.tokenize("第Ⅷ章", language: .swift)
        _ = SyntaxHighlighter.tokenize("x²", language: .swift)
        _ = SyntaxHighlighter.tokenize("①②③", language: .python)
    }

    @Test("各种奇怪输入都能跑完并给出合法范围", .timeLimit(.minutes(1)))
    func terminatesOnHostileInput() {
        let samples = [
            "@$_#%^&*()", "\\\\\\", "\"未闭合", "/*", "*/", "//",
            "🎉🎊", "\u{200B}\u{FEFF}", "a\u{0301}b",
            "$var @attr #tag", "０xFF", "１_０００",
            String(repeating: "@", count: 500),
            String(repeating: "１", count: 500),
        ]

        for language in [Language.swift, .javascript, .python, .cLike, .shell, .json] {
            for sample in samples {
                let tokens = SyntaxHighlighter.tokenize(sample, language: language)
                let count = Array(sample).count
                for token in tokens {
                    #expect(token.range.lowerBound >= 0)
                    #expect(token.range.upperBound <= count)
                    #expect(token.range.lowerBound < token.range.upperBound, "空范围说明有分支没前进")
                }
            }
        }
    }

    @Test("@ 在 Vue 模板里仍然被当作标识符起始")
    func atSignStillFormsIdentifier() {
        // 修死循环不能顺手把功能改掉：@interface 之类仍应作为一个整体被认出来
        let tokens = SyntaxHighlighter.tokenize("@interface Foo", language: .cLike)
        #expect(tokens.contains { $0.kind == .keyword })
    }

    @Test("token 之间不重叠，且按位置递增")
    func tokensAreOrderedAndDisjoint() {
        // 上层要按顺序拼接文本，重叠或乱序会导致内容重复或丢失
        let line = #"func f() { let s = "x" // 尾注释"#
        let tokens = SyntaxHighlighter.tokenize(line, language: .swift)
        for (previous, next) in zip(tokens, tokens.dropFirst()) {
            #expect(previous.range.upperBound <= next.range.lowerBound)
        }
    }
}
