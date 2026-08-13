import Foundation
import Testing

@testable import AIKit

@Suite("对话式操作计划")
struct OperationPlannerTests {

    private let context = OperationPlanner.Context(
        currentBranch: "main",
        stagedPaths: ["src/auth.swift"],
        unstagedPaths: ["README.md", "src/util.swift"],
        localBranches: ["main", "feature/x"],
        hasUpstream: true,
        ahead: 2,
        behind: 0
    )

    private func parse(_ json: String, context: OperationPlanner.Context? = nil) throws -> OperationPlan {
        try OperationPlanner.parse(json, context: context ?? self.context)
    }

    // MARK: - 正常计划

    @Test("多步计划按顺序解析")
    func parsesMultiStepPlan() throws {
        let json = """
            {"understanding":"把 README 暂存后提交",
             "steps":[
               {"action":"stage","args":{"paths":["README.md"]},"reason":"先暂存文档改动"},
               {"action":"commit","args":{"message":"docs: 补充说明"},"reason":"提交它"}
             ]}
            """

        guard case let .plan(understanding, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }

        #expect(understanding == "把 README 暂存后提交")
        #expect(steps.count == 2)
        #expect(steps[0].action == .stage(paths: ["README.md"]))
        #expect(steps[1].action == .commit(message: "docs: 补充说明"))
        #expect(steps[0].reason == "先暂存文档改动")
    }

    @Test("听不懂时反问而不是硬凑")
    func returnsClarification() throws {
        // 让模型在没听懂时也硬凑一个计划出来，比它直说「我不确定」危险得多
        let json = #"{"clarification":"你说的「那个文件」是指哪一个？"}"#

        guard case let .needsClarification(question) = try parse(json) else {
            Issue.record("应当反问")
            return
        }
        #expect(question.contains("哪一个"))
    }

    @Test("白名单表达不了的直说不支持")
    func returnsUnsupported() throws {
        let json = #"{"unsupported":"我没有办法直接改写远程仓库的历史。"}"#

        guard case .unsupported = try parse(json) else {
            Issue.record("应当返回不支持")
            return
        }
    }

    // MARK: - 安全约束

    @Test("编造出来的路径被丢掉")
    func dropsFabricatedPaths() throws {
        // 模型编一个不存在的路径，执行时最好的结果是报错，
        // 最坏的结果是动到了别的文件
        let json = """
            {"understanding":"x","steps":[
              {"action":"stage","args":{"paths":["README.md","不存在的文件.swift"]},"reason":"r"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps[0].action == .stage(paths: ["README.md"]))
    }

    @Test("整步的路径都不存在时丢掉这一步")
    func dropsStepWhenNoPathSurvives() throws {
        let json = """
            {"understanding":"x","steps":[
              {"action":"stage","args":{"paths":["假的.swift"]},"reason":"r"},
              {"action":"commit","args":{"message":"真的"},"reason":"r"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps.count == 1)
        #expect(steps[0].action == .commit(message: "真的"))
    }

    @Test("只能暂存未暂存的、取消暂存已暂存的")
    func respectsStagingDirection() throws {
        // 把已暂存的文件再 stage 一次是无意义的，模型偶尔会搞混
        let json = """
            {"understanding":"x","steps":[
              {"action":"stage","args":{"paths":["src/auth.swift"]},"reason":"这个已经暂存了"},
              {"action":"unstage","args":{"paths":["src/auth.swift"]},"reason":"这个才对"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps.count == 1)
        #expect(steps[0].action == .unstage(paths: ["src/auth.swift"]))
    }

    @Test("切到不存在的分支被拦下")
    func rejectsSwitchToUnknownBranch() throws {
        let json = """
            {"understanding":"x","steps":[
              {"action":"switch_branch","args":{"name":"不存在的分支"},"reason":"r"},
              {"action":"switch_branch","args":{"name":"feature/x"},"reason":"r"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps.count == 1)
        #expect(steps[0].action == .switchBranch(name: "feature/x"))
    }

    @Test("新建分支可以用清单外的名字")
    func allowsNewBranchName() throws {
        // create_branch 是唯一允许出现新名字的地方
        let json = """
            {"understanding":"x","steps":[
              {"action":"create_branch","args":{"name":"feature/全新的","from":"main"},"reason":"r"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps[0].action == .createBranch(name: "feature/全新的", from: "main"))
    }

    @Test("认不出的动作名被丢掉")
    func dropsUnknownActions() throws {
        // 模型发明的动作绝不能被当成什么都不做地放过去，
        // 更不能被当成某个近似动作
        let json = """
            {"understanding":"x","steps":[
              {"action":"force_push","args":{},"reason":"危险"},
              {"action":"reset_hard","args":{},"reason":"也危险"},
              {"action":"fetch","args":{},"reason":"这个可以"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps.count == 1)
        #expect(steps[0].action == .fetch)
    }

    @Test("没有 upstream 时 push 强制带 --set-upstream")
    func forcesSetUpstreamWhenMissing() throws {
        // 不管模型怎么说，没有 upstream 时不带这个参数必然失败
        let noUpstream = OperationPlanner.Context(
            currentBranch: "topic", stagedPaths: [], unstagedPaths: [],
            localBranches: ["topic"], hasUpstream: false)

        let json = """
            {"understanding":"x","steps":[
              {"action":"push","args":{"set_upstream":false},"reason":"r"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json, context: noUpstream) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps[0].action == .push(setUpstream: true))
    }

    @Test("丢弃动作被标为会丢东西")
    func marksDiscardAsDestructive() throws {
        let json = """
            {"understanding":"x","steps":[
              {"action":"discard","args":{"paths":["README.md"]},"reason":"会丢掉 README 的改动"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps[0].action.isDestructive)
        #expect(!PlannedAction.fetch.isDestructive)
    }

    @Test("一步都没剩下时算不支持，而不是返回空计划")
    func emptyPlanBecomesUnsupported() throws {
        // 返回空计划的话，界面上会显示一个「确认执行」按钮，点下去什么也不发生
        let json = #"{"understanding":"x","steps":[{"action":"编的动作","args":{},"reason":"r"}]}"#

        guard case .unsupported = try parse(json) else {
            Issue.record("应当返回不支持")
            return
        }
    }

    @Test("参数缺失时丢掉这一步")
    func dropsStepsWithMissingArgs() throws {
        let json = """
            {"understanding":"x","steps":[
              {"action":"commit","args":{},"reason":"没给信息"},
              {"action":"commit","args":{"message":"   "},"reason":"只有空白"},
              {"action":"commit","args":{"message":"有内容"},"reason":"这个可以"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps.count == 1)
        #expect(steps[0].action == .commit(message: "有内容"))
    }

    @Test("参数类型不对时不会崩")
    func toleratesWrongArgTypes() throws {
        let json = """
            {"understanding":"x","steps":[
              {"action":"stage","args":{"paths":"README.md"},"reason":"应该是数组"},
              {"action":"pull","args":{"rebase":"是的"},"reason":"应该是布尔"}
            ]}
            """

        guard case let .plan(_, steps) = try parse(json) else {
            Issue.record("应当返回计划")
            return
        }
        // stage 的参数类型不对被丢掉；pull 的布尔认不出按 false 处理
        #expect(steps.count == 1)
        #expect(steps[0].action == .pull(rebase: false))
    }

    // MARK: - 提示词

    @Test("提示词带上仓库现状")
    func promptCarriesRepositoryState() {
        let prompt = OperationPlanner.userPrompt(request: "帮我提交", context: context)

        #expect(prompt.contains("main"))
        #expect(prompt.contains("README.md"))
        #expect(prompt.contains("src/auth.swift"))
        #expect(prompt.contains("feature/x"))
        #expect(prompt.contains("帮我提交"))
    }

    @Test("没有 upstream 时提示词明说")
    func promptStatesMissingUpstream() {
        let noUpstream = OperationPlanner.Context(
            currentBranch: "topic", stagedPaths: [], unstagedPaths: [],
            localBranches: ["topic"], hasUpstream: false)

        #expect(OperationPlanner.userPrompt(request: "推上去", context: noUpstream).contains("还没有设置 upstream"))
    }

    @Test("系统提示词把白名单和禁令写清楚")
    func systemPromptPinsWhitelist() {
        let prompt = OperationPlanner.systemPrompt
        #expect(prompt.contains("只能"))
        #expect(prompt.contains("不能发明新的"))
        #expect(prompt.contains("不要编造"))
        #expect(prompt.contains("听不明白就问"))
        // 每个白名单动作都得在提示词里出现，否则模型不知道有它
        for verb in [
            "stage", "unstage", "commit", "create_branch", "switch_branch",
            "merge", "stash_push", "stash_pop", "fetch", "pull", "push", "discard",
        ] {
            #expect(prompt.contains(verb), "提示词里缺少动作 \(verb)")
        }
    }

    // MARK: - 端到端

    @Test("走一遍完整流程")
    func endToEnd() async throws {
        let payload =
            #"{"understanding":"暂存并提交 README","steps":[{"action":"stage","args":{"paths":["README.md"]},"reason":"先暂存"},{"action":"commit","args":{"message":"docs: x"},"reason":"再提交"}]}"#
        let escaped = payload.replacingOccurrences(of: "\"", with: "\\\"")

        let session = StubURLProtocol.makeSession(
            sse: """
                event: content_block_delta
                data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"\(escaped)"}}

                event: message_stop
                data: {"type":"message_stop"}

                """)

        let planner = OperationPlanner(
            provider: AnthropicProvider(apiKey: "sk-test", session: session),
            model: "claude-opus-5"
        )

        guard case let .plan(_, steps) = try await planner.plan(request: "把 README 提交了", context: context)
        else {
            Issue.record("应当返回计划")
            return
        }
        #expect(steps.count == 2)
    }

    @Test("空请求不发请求")
    func refusesEmptyRequest() async {
        let planner = OperationPlanner(
            provider: AnthropicProvider(apiKey: "sk-test", session: StubURLProtocol.makeSession(sse: "")),
            model: "claude-opus-5"
        )

        await #expect(throws: AIError.self) {
            _ = try await planner.plan(request: "   ", context: context)
        }
    }
}
