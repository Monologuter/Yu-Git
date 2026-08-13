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
