import Foundation

/// AI 允许提议的动作。
///
/// **这是一份白名单，不是建议。** 模型只能从这些动作里选，参数也各有类型——
/// 它永远拿不到「生成一条 git 命令字符串然后执行」的能力。那条路等于把
/// 命令注入的入口直接开给一个会被提示词左右的东西。
///
/// 加新动作要过两道：这里加一个 case，App 侧翻译成 ``GitOperation`` 时
/// 再校验一次参数。少任何一道都不行。
public enum PlannedAction: Sendable, Equatable {

    case stage(paths: [String])
    case unstage(paths: [String])
    case commit(message: String)
    case createBranch(name: String, from: String?)
    case switchBranch(name: String)
    case merge(branch: String)
    case stashPush(includingUntracked: Bool)
    case stashPop
    case fetch
    case pull(rebase: Bool)
    case push(setUpstream: Bool)
    /// 丢弃未提交的改动。**唯一真正找不回来的一类**，界面上要单独确认。
    case discard(paths: [String])

    /// 词表里的动作名，与提示词里给模型的名字一一对应。
    public var verb: String {
        switch self {
        case .stage: "stage"
        case .unstage: "unstage"
        case .commit: "commit"
        case .createBranch: "create_branch"
        case .switchBranch: "switch_branch"
        case .merge: "merge"
        case .stashPush: "stash_push"
        case .stashPop: "stash_pop"
        case .fetch: "fetch"
        case .pull: "pull"
        case .push: "push"
        case .discard: "discard"
        }
    }

    /// 这一步会不会丢东西。界面上据此决定要不要额外拦一道。
    public var isDestructive: Bool {
        if case .discard = self { true } else { false }
    }
}

/// 计划里的一步。
public struct PlannedStep: Sendable, Equatable, Identifiable {

    public let id: UUID
    public let action: PlannedAction
    /// 模型为什么加这一步。给用户看的，用来判断它有没有理解对。
    public let reason: String

    public init(id: UUID = UUID(), action: PlannedAction, reason: String) {
        self.id = id
        self.action = action
        self.reason = reason
    }
}

/// 一次对话的结果。
public enum OperationPlan: Sendable, Equatable {

    /// 模型听懂了，给出一份可预览的计划。
    case plan(understanding: String, steps: [PlannedStep])
    /// 模型不确定用户想做什么，反问一句。
    ///
    /// 这条路必须存在：让模型在没听懂时也硬凑一个计划出来，
    /// 比它直说「我不确定」危险得多。
    case needsClarification(question: String)
    /// 请求超出了白名单能表达的范围。
    case unsupported(reason: String)
}

/// 把一句中文变成一份可预览、可撤销的操作计划。
///
/// 远期规划里的「对话式 Git 操作」。三条不可动摇的规矩：
///
/// 1. **模型只能从白名单里选动作**，永远不生成可执行的命令字符串
/// 2. **计划一定先预览**，每一步显示等价 git 命令与中文解释，用户逐条过目
/// 3. **执行走 `RepoActor.perform`**，所以每一步都进时间线、都能撤销
public struct OperationPlanner: Sendable {

    /// 计划要读懂仓库状态并逐步推理，给足预算。
    static let maxTokens = 8192

    private let provider: any AIProvider
    private let model: String

    public init(provider: any AIProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// 仓库当前状态。模型据此判断哪些动作说得通。
    public struct Context: Sendable, Equatable {
        public let currentBranch: String?
        public let stagedPaths: [String]
        public let unstagedPaths: [String]
        public let localBranches: [String]
        public let hasUpstream: Bool
        public let ahead: Int
        public let behind: Int

        public init(
            currentBranch: String?,
            stagedPaths: [String],
            unstagedPaths: [String],
            localBranches: [String],
            hasUpstream: Bool,
            ahead: Int = 0,
            behind: Int = 0
        ) {
            self.currentBranch = currentBranch
            self.stagedPaths = stagedPaths
            self.unstagedPaths = unstagedPaths
            self.localBranches = localBranches
            self.hasUpstream = hasUpstream
            self.ahead = ahead
            self.behind = behind
        }
    }

    public func plan(request: String, context: Context) async throws -> OperationPlan {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AIError.malformedResponse("没有说要做什么")
        }

        let aiRequest = AIRequest(
            model: model,
            system: Self.systemPrompt,
            messages: [.user(Self.userPrompt(request: trimmed, context: context))],
            maxTokens: Self.maxTokens
        )

        return try Self.parse(try await provider.complete(aiRequest), context: context)
    }

    // MARK: - 提示词

    static let systemPrompt = """
        你在帮一位中文用户把一句话变成一组 Git 操作。

        你**只能**使用下面这些动作，不能发明新的，也不能给出 git 命令字符串：

        - stage {"paths": ["路径"]}        暂存指定文件
        - unstage {"paths": ["路径"]}      取消暂存
        - commit {"message": "提交信息"}   提交暂存区的内容
        - create_branch {"name": "分支名", "from": "起点，可省略"}
        - switch_branch {"name": "分支名"}
        - merge {"branch": "分支名"}
        - stash_push {"include_untracked": true}
        - stash_pop {}
        - fetch {}
        - pull {"rebase": false}
        - push {"set_upstream": false}
        - discard {"paths": ["路径"]}      丢弃未提交的改动，不可恢复

        规矩：
        - 路径必须来自我给你的文件清单，不要编造，也不要用通配符
        - 分支名必须来自我给你的分支清单，除非是 create_branch 要新建的
        - 步骤按执行顺序排，前一步的结果是后一步的前提
        - 用最少的步骤达成目的，不要顺带做用户没要求的事
        - 涉及 discard 时要在 reason 里明确写出会丢掉什么

        听不明白就问，不要硬凑一个计划。不能用上面的动作表达的，就说不支持。

        只输出一个 JSON 对象，不要加 markdown 代码围栏，不要写任何解释。三选一：

        {"understanding": "复述你的理解", "steps": [{"action": "动作名", "args": {...}, "reason": "为什么要这一步"}]}
        {"clarification": "要反问的话"}
        {"unsupported": "为什么做不到"}
        """

    static func userPrompt(request: String, context: Context) -> String {
        var sections: [String] = []

        var state: [String] = []
        state.append("当前分支：\(context.currentBranch ?? "（detached）")")
        state.append("本地分支：\(context.localBranches.isEmpty ? "（无）" : context.localBranches.joined(separator: "、"))")
        state.append(
            "已暂存：\(context.stagedPaths.isEmpty ? "（无）" : context.stagedPaths.joined(separator: "、"))")
        state.append(
            "未暂存：\(context.unstagedPaths.isEmpty ? "（无）" : context.unstagedPaths.joined(separator: "、"))")

        if context.hasUpstream {
            state.append("与远程：领先 \(context.ahead) 条，落后 \(context.behind) 条")
        } else {
            // 没有 upstream 时 push 必须带 --set-upstream，模型得知道
            state.append("与远程：当前分支还没有设置 upstream")
        }

        sections.append("仓库现在的状态：\n" + state.map { "- \($0)" }.joined(separator: "\n"))
        sections.append("用户说：\(request)")
        sections.append("请给出操作计划，输出 JSON。")

        return sections.joined(separator: "\n\n")
    }

    // MARK: - 解析

    static func parse(_ text: String, context: Context) throws -> OperationPlan {
        guard let json = CommitComposer.extractJSONObject(from: text) else {
            throw AIError.malformedResponse("模型没有返回 JSON：\(text.prefix(200))")
        }

        let raw: RawPlan
        do {
            raw = try JSONDecoder().decode(RawPlan.self, from: Data(json.utf8))
        } catch {
            throw AIError.malformedResponse("JSON 结构不符合预期：\(json.prefix(200))")
        }

        if let question = raw.clarification?.trimmingCharacters(in: .whitespacesAndNewlines),
            !question.isEmpty
        {
            return .needsClarification(question: question)
        }
        if let reason = raw.unsupported?.trimmingCharacters(in: .whitespacesAndNewlines),
            !reason.isEmpty
        {
            return .unsupported(reason: reason)
        }

        let steps = (raw.steps ?? []).compactMap { step in
            makeStep(step, context: context)
        }
        guard !steps.isEmpty else {
            return .unsupported(reason: "模型没有给出可执行的步骤")
        }

        return .plan(
            understanding: raw.understanding?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            steps: steps
        )
    }

    /// 把一步原始 JSON 变成一个白名单动作。
    ///
    /// 认不出的动作名、缺参数、路径不在清单里——一律丢弃这一步而不是猜。
    /// 模型编一个不存在的路径出来，执行时最好的结果是报错，最坏的结果是
    /// 动到了别的文件。
    private static func makeStep(_ raw: RawPlan.RawStep, context: Context) -> PlannedStep? {
        let args = raw.args ?? [:]
        let reason = raw.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        func paths(_ key: String, allowedIn allowed: [String]) -> [String]? {
            guard case let .array(values)? = args[key] else { return nil }
            let known = Set(allowed)
            // 只保留清单里真实存在的路径
            let filtered = values.compactMap { value -> String? in
                guard case let .string(path) = value, known.contains(path) else { return nil }
                return path
            }
            return filtered.isEmpty ? nil : filtered
        }

        func string(_ key: String) -> String? {
            guard case let .string(value)? = args[key] else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        func bool(_ key: String) -> Bool {
            if case let .bool(value)? = args[key] { return value }
            return false
        }

        let action: PlannedAction?
        switch raw.action {
        case "stage":
            // 可以暂存未暂存的，也可以暂存冲突已解决的文件
            action = paths("paths", allowedIn: context.unstagedPaths).map(PlannedAction.stage)
        case "unstage":
            action = paths("paths", allowedIn: context.stagedPaths).map(PlannedAction.unstage)
        case "commit":
            action = string("message").map(PlannedAction.commit)
        case "create_branch":
            action = string("name").map { PlannedAction.createBranch(name: $0, from: string("from")) }
        case "switch_branch":
            // 只能切到已存在的分支；要新建得先 create_branch
            action = string("name").flatMap {
                context.localBranches.contains($0) ? PlannedAction.switchBranch(name: $0) : nil
            }
        case "merge":
            action = string("branch").flatMap {
                context.localBranches.contains($0) ? PlannedAction.merge(branch: $0) : nil
            }
        case "stash_push":
            action = .stashPush(includingUntracked: bool("include_untracked"))
        case "stash_pop":
            action = .stashPop
        case "fetch":
            action = .fetch
        case "pull":
            action = .pull(rebase: bool("rebase"))
        case "push":
            // 没有 upstream 时必须带 --set-upstream，不管模型怎么说
            action = .push(setUpstream: bool("set_upstream") || !context.hasUpstream)
        case "discard":
            action = paths("paths", allowedIn: context.unstagedPaths).map(PlannedAction.discard)
        default:
            action = nil
        }

        guard let action else { return nil }
        return PlannedStep(action: action, reason: reason)
    }

    private struct RawPlan: Decodable {
        let understanding: String?
        let steps: [RawStep]?
        let clarification: String?
        let unsupported: String?

        struct RawStep: Decodable {
            let action: String
            let args: [String: JSONValue]?
            let reason: String?
        }
    }
}

/// 参数值可能是字符串、布尔或字符串数组，用一个宽松容器接住。
enum JSONValue: Decodable, Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case array([JSONValue])
    case other

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            // 认不出的形状不报错——单个参数看不懂不该让整份计划失败，
            // 上层校验会把缺参数的那一步丢掉
            self = .other
        }
    }
}
