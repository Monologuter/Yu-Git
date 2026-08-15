import Foundation
import Testing

@testable import AIKit

@Suite("Commit Composer")
struct CommitComposerTests {

    private let hunks = [
        ComposableHunk(
            id: "src/auth.swift#0", path: "src/auth.swift", heading: "func login()",
            patchText: "+  retry()", addedLines: 1),
        ComposableHunk(
            id: "src/auth.swift#1", path: "src/auth.swift", heading: "func logout()",
            patchText: "-  print(\"x\")", deletedLines: 1),
        ComposableHunk(
            id: "README.md#0", path: "README.md",
            patchText: "+安装说明", addedLines: 1),
    ]

    // MARK: - JSON 抠取

    @Test("干净的 JSON 原样取出")
    func extractsPlainJSON() {
        let json = #"{"commits":[]}"#
        #expect(CommitComposer.extractJSONObject(from: json) == json)
    }

    @Test("剥掉 markdown 围栏")
    func extractsFromCodeFence() {
        let text = "```json\n{\"commits\":[]}\n```"
        #expect(CommitComposer.extractJSONObject(from: text) == #"{"commits":[]}"#)
    }

    @Test("忽略 JSON 后面多写的话")
    func stopsAtMatchingBrace() {
        // 取第一个 { 到最后一个 } 的话，尾巴会被一起带进来
        let text = #"{"commits":[]}  以上就是我的分组建议。"#
        #expect(CommitComposer.extractJSONObject(from: text) == #"{"commits":[]}"#)
    }

    @Test("忽略 JSON 前面多写的话")
    func skipsLeadingProse() {
        let text = "好的，我来分组：\n{\"commits\":[]}"
        #expect(CommitComposer.extractJSONObject(from: text) == #"{"commits":[]}"#)
    }

    @Test("字符串里的花括号不参与配对")
    func ignoresBracesInsideStrings() {
        // diff 内容里出现花括号太常见了，不跳过字符串就会在这里截断
        let json = #"{"commits":[{"title":"fix: 补上 } 括号","hunks":["a"]}]}"#
        #expect(CommitComposer.extractJSONObject(from: json) == json)
    }

    @Test("转义引号不会误判字符串结束")
    func handlesEscapedQuotes() {
        let json = #"{"title":"他说 \"好\" 然后 {","hunks":[]}"#
        #expect(CommitComposer.extractJSONObject(from: json) == json)
    }

    @Test("没有 JSON 时返回 nil")
    func returnsNilWithoutJSON() {
        #expect(CommitComposer.extractJSONObject(from: "我不知道该怎么分组") == nil)
    }

    @Test("括号没配平时返回 nil")
    func returnsNilOnUnbalanced() {
        #expect(CommitComposer.extractJSONObject(from: #"{"commits":[ "#) == nil)
    }

    // MARK: - 解析

    @Test("正常分组")
    func parsesGroups() throws {
        let json = """
            {"commits":[
              {"title":"fix(auth): 登录重试","body":"超时后重试一次。","reason":"都在改登录流程","hunks":["src/auth.swift#0","src/auth.swift#1"]},
              {"title":"docs: 补充安装说明","reason":"文档改动，与代码无关","hunks":["README.md#0"]}
            ]}
            """

        let proposal = try CommitComposer.parse(json, hunks: hunks)

        #expect(proposal.commits.count == 2)
        #expect(proposal.commits[0].title == "fix(auth): 登录重试")
        #expect(proposal.commits[0].hunkIDs == ["src/auth.swift#0", "src/auth.swift#1"])
        #expect(proposal.commits[0].message == "fix(auth): 登录重试\n\n超时后重试一次。")
        // 没有正文时不要拼出多余的空行
        #expect(proposal.commits[1].message == "docs: 补充安装说明")
        #expect(proposal.unassignedHunkIDs.isEmpty)
    }

    @Test("漏掉的改动块会被列出来，不会悄悄丢")
    func reportsUnassignedHunks() throws {
        // 悄悄丢等于用户以为提交完了，实际还有改动留在工作区
        let json = #"{"commits":[{"title":"fix: 只管一块","hunks":["src/auth.swift#0"]}]}"#
        let proposal = try CommitComposer.parse(json, hunks: hunks)

        #expect(proposal.commits.count == 1)
        #expect(proposal.unassignedHunkIDs == ["src/auth.swift#1", "README.md#0"])
    }

    @Test("编造出来的编号被丢掉")
    func dropsUnknownHunkIDs() throws {
        let json = """
            {"commits":[{"title":"fix: 有真有假","hunks":["src/auth.swift#0","不存在的块#9"]}]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)
        #expect(proposal.commits[0].hunkIDs == ["src/auth.swift#0"])
    }

    @Test("同一块被分给两组时只算第一组")
    func deduplicatesAcrossGroups() throws {
        // 一块改动只能进一个提交，重复应用第二次必然失败
        let json = """
            {"commits":[
              {"title":"fix: 第一组","hunks":["src/auth.swift#0","README.md#0"]},
              {"title":"docs: 第二组","hunks":["README.md#0","src/auth.swift#1"]}
            ]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)

        #expect(proposal.commits[0].hunkIDs == ["src/auth.swift#0", "README.md#0"])
        #expect(proposal.commits[1].hunkIDs == ["src/auth.swift#1"])
    }

    @Test("空组被剔除")
    func dropsEmptyGroups() throws {
        let json = """
            {"commits":[
              {"title":"fix: 有内容","hunks":["src/auth.swift#0"]},
              {"title":"chore: 什么都没有","hunks":[]}
            ]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)
        #expect(proposal.commits.count == 1)
    }

    @Test("标题为空的组被剔除")
    func dropsUntitledGroups() throws {
        let json = """
            {"commits":[
              {"title":"   ","hunks":["src/auth.swift#0"]},
              {"title":"docs: 有标题","hunks":["README.md#0"]}
            ]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)
        #expect(proposal.commits.count == 1)
        #expect(proposal.commits[0].title == "docs: 有标题")
        // 被剔除那组占用的块要退回未分配，不能跟着一起消失
        #expect(proposal.unassignedHunkIDs.contains("src/auth.swift#1"))
    }

    @Test("完全无效的输出直接报错")
    func throwsOnUnusableOutput() {
        #expect(throws: AIError.self) {
            _ = try CommitComposer.parse("我拒绝分组", hunks: hunks)
        }
        #expect(throws: AIError.self) {
            _ = try CommitComposer.parse(#"{"commits":[]}"#, hunks: hunks)
        }
    }

    @Test("JSON 结构不对时报错而不是崩")
    func throwsOnWrongShape() {
        #expect(throws: AIError.self) {
            _ = try CommitComposer.parse(#"{"groups":[{"name":"x"}]}"#, hunks: hunks)
        }
    }

    // MARK: - 顺序

    @Test("被依赖的组排到前面")
    func ordersDependenciesFirst() throws {
        // bisect 要有意义，每个中间状态都得能编译过——调用方不能排在定义之前
        let json = """
            {"commits":[
              {"key":"caller","title":"feat: 调用新函数","dependsOn":["def"],"hunks":["src/auth.swift#0"]},
              {"key":"def","title":"feat: 加上新函数","dependsOn":[],"hunks":["src/auth.swift#1"]}
            ]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)

        #expect(proposal.commits.map(\.title) == ["feat: 加上新函数", "feat: 调用新函数"])
        #expect(proposal.orderingNote?.contains("已按依赖调整顺序") == true)
        #expect(proposal.commits[1].dependsOn == [proposal.commits[0].id])
    }

    @Test("没有依赖时不无谓重排")
    func keepsOriginalOrderWithoutDependencies() throws {
        let json = """
            {"commits":[
              {"key":"a","title":"fix: 第一组","hunks":["src/auth.swift#0"]},
              {"key":"b","title":"docs: 第二组","hunks":["README.md#0"]}
            ]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)

        #expect(proposal.commits.map(\.title) == ["fix: 第一组", "docs: 第二组"])
        #expect(proposal.orderingNote == nil, "没动过顺序就不该冒出提示")
    }

    @Test("依赖成环时保留原顺序并说明")
    func reportsDependencyCycle() throws {
        // 硬排一个顺序出来只是把问题藏起来
        let json = """
            {"commits":[
              {"key":"a","title":"feat: 甲","dependsOn":["b"],"hunks":["src/auth.swift#0"]},
              {"key":"b","title":"feat: 乙","dependsOn":["a"],"hunks":["README.md#0"]}
            ]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)

        #expect(proposal.commits.map(\.title) == ["feat: 甲", "feat: 乙"])
        #expect(proposal.orderingNote?.contains("互相依赖") == true)
        #expect(proposal.orderingNote?.contains("feat: 甲") == true)
    }

    @Test("指向不存在的 key 与指向自己的依赖都被丢掉")
    func dropsBogusDependencies() throws {
        let json = """
            {"commits":[
              {"key":"a","title":"feat: 甲","dependsOn":["a","查无此组"],"hunks":["src/auth.swift#0"]}
            ]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)

        #expect(proposal.commits[0].dependsOn.isEmpty)
        #expect(proposal.orderingNote == nil)
    }

    @Test("依赖指向了被剔除的空组时不会卡住")
    func survivesDependenciesOnDroppedGroups() throws {
        // 空组会被剔掉，指着它的依赖如果还算数，整个排序就永远排不完
        let json = """
            {"commits":[
              {"key":"empty","title":"chore: 空的","hunks":[]},
              {"key":"real","title":"feat: 有内容","dependsOn":["empty"],"hunks":["src/auth.swift#0"]}
            ]}
            """
        let proposal = try CommitComposer.parse(json, hunks: hunks)

        #expect(proposal.commits.count == 1)
        #expect(proposal.commits[0].title == "feat: 有内容")
        #expect(proposal.orderingNote == nil)
    }

    // MARK: - 提示词

    @Test("提示词带上清单和每块的内容")
    func promptCarriesInventoryAndDetails() {
        let prompt = CommitComposer.userPrompt(hunks: hunks)

        for hunk in hunks {
            #expect(prompt.contains(hunk.id))
            #expect(prompt.contains(hunk.patchText))
        }
        #expect(prompt.contains("func login()"))
        #expect(prompt.contains("共 3 块"))
    }

    @Test("系统提示词要求按意图分组且输出纯 JSON")
    func systemPromptPinsRules() {
        let prompt = CommitComposer.systemPrompt
        #expect(prompt.contains("意图"))
        #expect(prompt.contains("Conventional Commits"))
        #expect(prompt.contains("代码围栏"))
        #expect(prompt.contains("恰好出现一次"))
        // 顺序和分组一样重要：编不过的中间状态让 bisect 失去意义
        #expect(prompt.contains("bisect"))
        #expect(prompt.contains("dependsOn"))
    }

    // MARK: - 端到端

    @Test("走一遍完整流程")
    func endToEnd() async throws {
        let payload = """
            {"commits":[{"title":"fix(auth): 登录重试","reason":"同一处逻辑","hunks":["src/auth.swift#0","src/auth.swift#1"]},{"title":"docs: 补说明","reason":"文档","hunks":["README.md#0"]}]}
            """
        // JSON 里的引号要转义成 SSE 事件里的合法字符串
        let escaped =
            payload
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let session = StubURLProtocol.makeSession(
            sse: """
                event: content_block_delta
                data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\(escaped)"}}

                event: message_stop
                data: {"type":"message_stop"}

                """)

        let composer = CommitComposer(
            provider: AnthropicProvider(apiKey: "sk-test", session: session),
            model: "claude-opus-5"
        )

        let proposal = try await composer.propose(hunks: hunks)
        #expect(proposal.commits.count == 2)
        #expect(proposal.unassignedHunkIDs.isEmpty)
    }

    @Test("没有改动时不发请求")
    func refusesEmptyInput() async {
        let composer = CommitComposer(
            provider: AnthropicProvider(apiKey: "sk-test", session: StubURLProtocol.makeSession(sse: "")),
            model: "claude-opus-5"
        )

        await #expect(throws: AIError.self) {
            _ = try await composer.propose(hunks: [])
        }
    }
}
