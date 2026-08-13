import Foundation
import Testing

@testable import AIKit

@Suite("Diff 评审")
struct DiffReviewerTests {

    // MARK: - 解析

    @Test("正常评审结果")
    func parsesReview() throws {
        let json = """
            {"summary":"给登录接口加上了重试，同时调整了超时配置。",
             "findings":[
               {"severity":"critical","path":"src/auth.swift","line":42,
                "title":"重试时没有校验 token 是否已过期",
                "detail":"过期后重试会连续失败三次，还可能触发风控。"},
               {"severity":"nitpick","path":"src/config.swift","title":"import 顺序"}
             ]}
            """

        let review = try DiffReviewer.parse(json)
        #expect(review.summary.contains("重试"))
        #expect(review.findings.count == 2)
        #expect(review.hasBlockingConcerns)

        let first = try #require(review.findings.first)
        #expect(first.severity == .critical)
        #expect(first.line == 42)
        #expect(first.path == "src/auth.swift")
    }

    @Test("按风险排序：鉴权置顶，格式化垫底")
    func sortsBySeverity() throws {
        // PRD 要求的导航方式：500 行 diff 里最要紧的两处，
        // 不该和 30 条空格改动混在一起
        let json = """
            {"summary":"x","findings":[
              {"severity":"nitpick","path":"a","title":"空格"},
              {"severity":"critical","path":"b","title":"越权"},
              {"severity":"info","path":"c","title":"命名"},
              {"severity":"warning","path":"d","title":"空值"}
            ]}
            """

        let review = try DiffReviewer.parse(json)
        #expect(review.findings.map(\.severity) == [.critical, .warning, .info, .nitpick])
    }

    @Test("同级内保持模型给的顺序")
    func stableWithinSeverity() throws {
        // 模型通常按文件顺序走，打乱它反而更难对照
        let json = """
            {"summary":"x","findings":[
              {"severity":"warning","path":"第一个","title":"A"},
              {"severity":"warning","path":"第二个","title":"B"},
              {"severity":"warning","path":"第三个","title":"C"}
            ]}
            """
        let review = try DiffReviewer.parse(json)
        #expect(review.findings.map(\.path) == ["第一个", "第二个", "第三个"])
    }

    @Test("认不出的等级按 info 算")
    func unknownSeverityBecomesInfo() throws {
        // 不能按 nitpick 算——那会被默认折叠，用户根本看不见
        let json = #"{"summary":"x","findings":[{"severity":"超级严重","path":"a","title":"T"}]}"#
        let review = try DiffReviewer.parse(json)
        #expect(review.findings.first?.severity == .info)
    }

    @Test("非法行号当作定位不到")
    func rejectsInvalidLineNumbers() throws {
        let json = """
            {"summary":"x","findings":[
              {"severity":"info","path":"a","line":0,"title":"零"},
              {"severity":"info","path":"b","line":-3,"title":"负数"},
              {"severity":"info","path":"c","title":"没给"}
            ]}
            """
        let review = try DiffReviewer.parse(json)
        #expect(review.findings.allSatisfy { $0.line == nil })
    }

    @Test("没有标题的意见被丢掉")
    func dropsUntitledFindings() throws {
        let json = """
            {"summary":"x","findings":[
              {"severity":"info","path":"a","title":"   "},
              {"severity":"info","path":"b","title":"有标题"}
            ]}
            """
        let review = try DiffReviewer.parse(json)
        #expect(review.findings.count == 1)
    }

    @Test("没有问题时也是合法结果")
    func acceptsCleanReview() throws {
        let review = try DiffReviewer.parse(#"{"summary":"改动很直接，没有发现问题。","findings":[]}"#)
        #expect(review.findings.isEmpty)
        #expect(!review.hasBlockingConcerns)
    }

    @Test("既没摘要也没意见时报错")
    func throwsOnEmptyReview() {
        #expect(throws: AIError.self) {
            _ = try DiffReviewer.parse(#"{"summary":"","findings":[]}"#)
        }
    }

    @Test("剥围栏、忽略前后废话")
    func toleratesWrappedOutput() throws {
        let text = "我看了一下：\n```json\n{\"summary\":\"没问题\",\"findings\":[]}\n```"
        #expect(try DiffReviewer.parse(text).summary == "没问题")
    }

    @Test("不是 JSON 时报错")
    func throwsOnNonJSON() {
        #expect(throws: AIError.self) {
            _ = try DiffReviewer.parse("这份改动我看不懂")
        }
    }

    // MARK: - 分级行为

    @Test("只有格式化意见时不算需要重点确认")
    func nitpicksAreNotBlocking() throws {
        let json = #"{"summary":"x","findings":[{"severity":"nitpick","path":"a","title":"空格"}]}"#
        #expect(!(try DiffReviewer.parse(json).hasBlockingConcerns))
    }

    @Test("格式化默认折叠，其余默认展开")
    func expansionDefaults() {
        #expect(!ReviewFinding.Severity.nitpick.isExpandedByDefault)
        for severity in [ReviewFinding.Severity.critical, .warning, .info] {
            #expect(severity.isExpandedByDefault)
        }
    }

    @Test("按等级取子集")
    func filtersBySeverity() throws {
        let json = """
            {"summary":"x","findings":[
              {"severity":"critical","path":"a","title":"A"},
              {"severity":"critical","path":"b","title":"B"},
              {"severity":"info","path":"c","title":"C"}
            ]}
            """
        let review = try DiffReviewer.parse(json)
        #expect(review.findings(of: .critical).count == 2)
        #expect(review.findings(of: .warning).isEmpty)
    }

    // MARK: - 提示词

    @Test("系统提示词交代了分级依据和克制原则")
    func systemPromptPinsRules() {
        let prompt = DiffReviewer.systemPrompt
        #expect(prompt.contains("鉴权"))
        #expect(prompt.contains("宁缺毋滥"))
        #expect(prompt.contains("代码围栏"))
        // 只看 diff，不该猜需求
        #expect(prompt.contains("看不到需求文档"))
    }

    @Test("上下文被删改时如实告诉模型")
    func promptDisclosesRedaction() {
        let redaction = ContextRedactor().redact(
            diff: """
                diff --git a/.env b/.env
                index 1..2 100644
                --- a/.env
                +++ b/.env
                @@ -1 +1 @@
                +KEY=值
                """)

        let prompt = DiffReviewer.userPrompt(diff: "（内容）", branchName: "main", redaction: redaction)
        #expect(prompt.contains("敏感"))
        #expect(prompt.contains(".env"))
        #expect(prompt.contains("main"))
    }

    // MARK: - 端到端

    @Test("走一遍完整流程，脱敏结果一并带出")
    func endToEnd() async throws {
        let payload = #"{"summary":"加了重试","findings":[{"severity":"warning","path":"a.swift","title":"没有上限"}]}"#
        let escaped = payload.replacingOccurrences(of: "\"", with: "\\\"")

        let session = StubURLProtocol.makeSession(
            sse: """
                event: content_block_delta
                data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\(escaped)"}}

                event: message_stop
                data: {"type":"message_stop"}

                """)

        let reviewer = DiffReviewer(
            provider: AnthropicProvider(apiKey: "sk-test", session: session),
            model: "claude-opus-5"
        )

        // 含一个敏感文件，评审结果里要带上「哪些没给 AI 看」
        let diff = """
            diff --git a/a.swift b/a.swift
            index 1..2 100644
            --- a/a.swift
            +++ b/a.swift
            @@ -1 +1,2 @@
             func f() {}
            +func retry() {}
            diff --git a/.env b/.env
            index 3..4 100644
            --- a/.env
            +++ b/.env
            @@ -1 +1 @@
            +KEY=值
            """

        let review = try await reviewer.review(diff: diff, branchName: "main")
        #expect(review.summary == "加了重试")
        #expect(review.findings.count == 1)
        #expect(review.redaction?.excludedPaths == [".env"])
    }

    @Test("没有内容时不发请求")
    func refusesEmptyDiff() async {
        let reviewer = DiffReviewer(
            provider: AnthropicProvider(apiKey: "sk-test", session: StubURLProtocol.makeSession(sse: "")),
            model: "claude-opus-5"
        )

        await #expect(throws: AIError.self) {
            _ = try await reviewer.review(diff: "")
        }
    }
}
