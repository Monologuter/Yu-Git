import Foundation
import Testing

@testable import AIKit

@Suite("提交信息生成")
struct CommitMessageTests {

    static let diff = """
        diff --git a/src/auth.swift b/src/auth.swift
        index ef02c77..d69668b 100644
        --- a/src/auth.swift
        +++ b/src/auth.swift
        @@ -1,3 +1,4 @@
         func login() {
        +  retry()
         }
        """

    // MARK: - 清洗输出

    @Test("剥掉 markdown 围栏")
    func stripsCodeFence() {
        // 提示词已经要求不要加围栏，但模型不是 100% 听话，
        // 而围栏一旦漏进提交信息就永远留在仓库历史里
        let raw = """
            ```
            fix(auth): 登录失败时自动重试

            超时会话之前直接报错，现在重试一次。
            ```
            """

        #expect(
            CommitMessageGenerator.sanitize(raw) == """
                fix(auth): 登录失败时自动重试

                超时会话之前直接报错，现在重试一次。
                """)
    }

    @Test("带语言标记的围栏也剥掉")
    func stripsFenceWithLanguageTag() {
        let raw = "```text\nfix: 修复超时\n```"
        #expect(CommitMessageGenerator.sanitize(raw) == "fix: 修复超时")
    }

    @Test("正文里的围栏不动")
    func keepsInnerFences() {
        // 提交正文里贴一段代码是合法的，只有首尾成对的围栏才该剥
        let raw = "fix: 修正示例\n\n之前写成了：\n```\nfoo()\n```"
        #expect(CommitMessageGenerator.sanitize(raw) == raw)
    }

    @Test("去掉首尾空行")
    func trimsBlankLines() {
        #expect(CommitMessageGenerator.sanitize("\n\n  fix: 修复\n\n") == "fix: 修复")
    }

    @Test("没有围栏时原样返回")
    func leavesPlainTextAlone() {
        let raw = "feat: 新增导出功能\n\n支持导出为 CSV。"
        #expect(CommitMessageGenerator.sanitize(raw) == raw)
    }

    // MARK: - 提示词

    @Test("提示词带上分支、文件和最近的提交风格")
    func promptCarriesContext() {
        let input = CommitMessageGenerator.Input(
            stagedDiff: Self.diff,
            stagedPaths: ["src/auth.swift"],
            branchName: "feature/retry",
            recentSubjects: ["fix(net): 超时后重连", "feat(ui): 新增暗色主题"]
        )
        let redacted = ContextRedactor().redact(diff: Self.diff)
        let prompt = CommitMessageGenerator.userPrompt(input, redacted: redacted)

        #expect(prompt.contains("feature/retry"))
        #expect(prompt.contains("src/auth.swift"))
        #expect(prompt.contains("fix(net): 超时后重连"))
        #expect(prompt.contains("retry()"))
    }

    @Test("上下文被删改时如实告诉模型")
    func promptDisclosesRedaction() {
        // 不说的话，模型会对着残缺的 diff 编出一个完整的故事
        let withSecret =
            Self.diff + """

                diff --git a/.env b/.env
                index 1..2 100644
                --- a/.env
                +++ b/.env
                @@ -1 +1 @@
                +KEY=值
                """

        let input = CommitMessageGenerator.Input(stagedDiff: withSecret)
        let redacted = ContextRedactor().redact(diff: withSecret)
        let prompt = CommitMessageGenerator.userPrompt(input, redacted: redacted)

        #expect(prompt.contains("敏感"))
        #expect(prompt.contains(".env"))
        #expect(!prompt.contains("KEY=值"))
    }

    @Test("系统提示词约束了格式")
    func systemPromptPinsFormat() {
        let prompt = CommitMessageGenerator.systemPrompt
        #expect(prompt.contains("Conventional Commits"))
        #expect(prompt.contains("中文"))
        #expect(prompt.contains("代码围栏"))
    }

    // MARK: - 端到端

    @Test("流式生成拼出完整提交信息")
    func streamsFullMessage() async throws {
        let session = StubURLProtocol.makeSession(
            sse: """
                event: content_block_delta
                data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"fix(auth): "}}

                event: content_block_delta
                data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"登录失败时自动重试"}}

                event: message_stop
                data: {"type":"message_stop"}

                """)

        let generator = CommitMessageGenerator(
            provider: AnthropicProvider(apiKey: "sk-test", session: session),
            model: "claude-opus-5"
        )

        let stream = try generator.generate(
            CommitMessageGenerator.Input(stagedDiff: Self.diff, stagedPaths: ["src/auth.swift"]))

        var text = ""
        for try await delta in stream.text { text += delta }

        #expect(text == "fix(auth): 登录失败时自动重试")
        #expect(stream.redaction.summary == nil)
    }

    @Test("暂存区为空时直接报错，不白发一次请求")
    func rejectsEmptyStage() {
        let generator = CommitMessageGenerator(
            provider: AnthropicProvider(apiKey: "sk-test", session: StubURLProtocol.makeSession(sse: "")),
            model: "claude-opus-5"
        )

        #expect(throws: AIError.self) {
            _ = try generator.generate(CommitMessageGenerator.Input(stagedDiff: ""))
        }
    }

    @Test("全是敏感文件时仍能靠文件名生成")
    func stillWorksWhenEverythingRedacted() throws {
        // diff 全被排除，但文件名列表还在——总比什么都不给强
        let onlySecrets = """
            diff --git a/.env b/.env
            index 1..2 100644
            --- a/.env
            +++ b/.env
            @@ -1 +1 @@
            +KEY=值
            """

        let session = StubURLProtocol.makeSession(
            sse: """
                event: content_block_delta
                data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"chore: 更新环境变量配置"}}

                event: message_stop
                data: {"type":"message_stop"}

                """)

        let generator = CommitMessageGenerator(
            provider: AnthropicProvider(apiKey: "sk-test", session: session),
            model: "claude-opus-5"
        )

        let stream = try generator.generate(
            CommitMessageGenerator.Input(stagedDiff: onlySecrets, stagedPaths: [".env"]))
        #expect(stream.redaction.excludedPaths == [".env"])
    }
}
