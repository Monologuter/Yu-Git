import Foundation
import Testing

@testable import AIKit

@Suite("AI 解冲突")
struct ConflictResolverTests {

    private let conflict = ConflictContext(
        path: "src/config.swift",
        index: 0,
        ours: ["let timeout = 30", "let retries = 3"],
        theirs: ["let timeout = 60"],
        base: ["let timeout = 10"],
        contextBefore: ["struct Config {"],
        contextAfter: ["}"]
    )

    // MARK: - 解析

    @Test("正常建议")
    func parsesSuggestion() throws {
        let json = """
            {"resolved":["let timeout = 60","let retries = 3"],
             "reason":"双方都在改超时值，对方改得更大；我方另外加了重试次数，两处不冲突，都保留。",
             "confidence":"high"}
            """

        let suggestion = try ConflictResolver.parse(json)
        #expect(suggestion.resolvedLines == ["let timeout = 60", "let retries = 3"])
        #expect(suggestion.confidence == .high)
        #expect(suggestion.reason.contains("都保留"))
    }

    @Test("空数组表示整块删掉")
    func parsesEmptyResolution() throws {
        let suggestion = try ConflictResolver.parse(#"{"resolved":[],"confidence":"medium"}"#)
        #expect(suggestion.resolvedLines.isEmpty)
        #expect(suggestion.reason.isEmpty)
    }

    @Test("认不出的置信度按最低算")
    func unknownConfidenceFallsBackToLow() throws {
        // 宁可让用户多看一眼，也不要把一个说不清的建议标成「把握较大」
        for raw in [#"{"resolved":["x"],"confidence":"很高"}"#, #"{"resolved":["x"]}"#] {
            #expect(try ConflictResolver.parse(raw).confidence == .low)
        }
    }

    @Test("建议里还带冲突标记时报错")
    func rejectsSuggestionWithMarkers() {
        // 写回去等于什么都没解决，而 git add 不会拦，会一路提交出去
        let json = """
            {"resolved":["<<<<<<< HEAD","let timeout = 30","=======","let timeout = 60",">>>>>>> feature"],
             "confidence":"high"}
            """
        #expect(throws: AIError.self) {
            _ = try ConflictResolver.parse(json)
        }
    }

    @Test("剥围栏、忽略前后废话")
    func toleratesWrappedOutput() throws {
        let text = """
            我来分析一下这个冲突：
            ```json
            {"resolved":["合并结果"],"reason":"理由","confidence":"medium"}
            ```
            以上。
            """
        let suggestion = try ConflictResolver.parse(text)
        #expect(suggestion.resolvedLines == ["合并结果"])
        #expect(suggestion.confidence == .medium)
    }

    @Test("完全不是 JSON 时报错")
    func throwsOnNonJSON() {
        #expect(throws: AIError.self) {
            _ = try ConflictResolver.parse("这个冲突我解不了")
        }
    }

    @Test("结构不对时报错而不是崩")
    func throwsOnWrongShape() {
        #expect(throws: AIError.self) {
            _ = try ConflictResolver.parse(#"{"answer":"取我方的"}"#)
        }
    }

    // MARK: - 提示词

    @Test("提示词带上三方内容与上下文")
    func promptCarriesThreeWayContext() {
        let prompt = ConflictResolver.userPrompt(conflict)

        #expect(prompt.contains("src/config.swift"))
        #expect(prompt.contains("let timeout = 10"))  // base
        #expect(prompt.contains("let retries = 3"))  // ours
        #expect(prompt.contains("let timeout = 60"))  // theirs
        #expect(prompt.contains("struct Config {"))  // 上文
        #expect(prompt.contains("}"))  // 下文
    }

    @Test("没有共同祖先时明说")
    func promptStatesMissingBase() {
        // 不说的话模型会以为自己看到了全部信息，给出过高的置信度
        let noBase = ConflictContext(
            path: "a.swift", index: 0, ours: ["A"], theirs: ["B"], base: nil)
        let prompt = ConflictResolver.userPrompt(noBase)

        #expect(prompt.contains("没有共同祖先"))
    }

    @Test("系统提示词交代了判断顺序和置信度规则")
    func systemPromptPinsRules() {
        let prompt = ConflictResolver.systemPrompt
        #expect(prompt.contains("共同祖先"))
        #expect(prompt.contains("矛盾"))
        #expect(prompt.contains("confidence"))
        #expect(prompt.contains("代码围栏"))
        // 没有 base 时不许给高置信度
        #expect(prompt.contains("不要高于 medium"))
    }

    @Test("置信度排序：低的排前面，提醒用户先看")
    func lowConfidenceSortsFirst() {
        let sorted = [
            ConflictSuggestion.Confidence.high,
            .low,
            .medium,
        ].sorted { $0.sortWeight < $1.sortWeight }

        #expect(sorted == [.low, .medium, .high])
    }

    // MARK: - 端到端

    @Test("走一遍完整流程")
    func endToEnd() async throws {
        let payload = #"{"resolved":["let timeout = 60","let retries = 3"],"reason":"两处不冲突","confidence":"high"}"#
        let escaped = payload.replacingOccurrences(of: "\"", with: "\\\"")

        let session = StubURLProtocol.makeSession(
            sse: """
                event: content_block_delta
                data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\(escaped)"}}

                event: message_stop
                data: {"type":"message_stop"}

                """)

        let resolver = ConflictResolver(
            provider: AnthropicProvider(apiKey: "sk-test", session: session),
            model: "claude-opus-5"
        )

        let suggestion = try await resolver.suggest(for: conflict)
        #expect(suggestion.resolvedLines.count == 2)
        #expect(suggestion.confidence == .high)
    }
}
