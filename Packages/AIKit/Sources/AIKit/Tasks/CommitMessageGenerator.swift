import Foundation

/// 根据暂存区的改动写提交信息。
///
/// 生成的结果**直接流进提交框，可编辑、可全部删掉重写**——这是 PRD 的 AI 铁律：
/// AI 给的是草稿而不是结论，用户始终握着最后一支笔。
public struct CommitMessageGenerator: Sendable {

    /// 提交信息很短，但 `max_tokens` 在部分模型上是「思考 + 正文」的总上限。
    /// 给宽一点不会多花钱（只按实际生成量计费），却能避免思考占满预算后正文被截断。
    static let maxTokens = 4096

    private let provider: any AIProvider
    private let model: String
    private let redactor = ContextRedactor()

    public init(provider: any AIProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// 生成的输入。
    public struct Input: Sendable {
        /// `git diff --cached` 的输出。
        public let stagedDiff: String
        /// 暂存的文件路径，用于在 diff 被截断时仍能说清改了哪些文件。
        public let stagedPaths: [String]
        public let branchName: String?
        /// 最近几条提交标题，让 AI 跟上这个仓库既有的书写风格。
        public let recentSubjects: [String]

        public init(
            stagedDiff: String,
            stagedPaths: [String] = [],
            branchName: String? = nil,
            recentSubjects: [String] = []
        ) {
            self.stagedDiff = stagedDiff
            self.stagedPaths = stagedPaths
            self.branchName = branchName
            self.recentSubjects = recentSubjects
        }
    }

    /// 生成结果的流。
    public struct Stream: Sendable {
        /// 脱敏过程做了什么，需要如实展示给用户。
        public let redaction: ContextRedactor.Result
        public let text: AsyncThrowingStream<String, any Error>
    }

    /// 开始生成。文本逐段流出，调用方边收边往提交框里写。
    public func generate(_ input: Input) throws -> Stream {
        let redacted = redactor.redact(diff: input.stagedDiff)

        guard !redacted.text.isEmpty || !input.stagedPaths.isEmpty else {
            throw AIError.malformedResponse("暂存区没有可分析的改动")
        }

        let request = AIRequest(
            model: model,
            system: Self.systemPrompt,
            messages: [.user(Self.userPrompt(input, redacted: redacted))],
            maxTokens: Self.maxTokens
        )

        let stream = provider.stream(request)
        return Stream(
            redaction: redacted,
            text: AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await event in stream {
                            if case let .textDelta(delta) = event { continuation.yield(delta) }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        )
    }

    // MARK: - 提示词

    static let systemPrompt = """
        你是一位资深工程师，正在为一次 Git 提交撰写提交信息。

        格式要求（Conventional Commits，描述用中文）：
        - 首行：`类型(范围): 描述`，范围可省略，整行不超过 50 个字符
        - 类型只能是 feat、fix、docs、style、refactor、perf、test、build、ci、chore、revert 之一
        - 描述用祈使句陈述这次改动做了什么，不加句号
        - 若改动值得展开，空一行后写正文，每行不超过 72 个字符
        - 正文说明「为什么这么改」，而不是逐行复述 diff 已经写明的内容

        输出要求：
        - 直接输出提交信息本身，不要加 markdown 代码围栏，不要加任何解释或前后缀
        - 不要写「本次提交」「这个改动」这类空话开头
        - 拿不准改动意图时，如实描述观察到的事实，不要臆测动机
        """

    static func userPrompt(_ input: Input, redacted: ContextRedactor.Result) -> String {
        var sections: [String] = []

        if let branch = input.branchName {
            sections.append("当前分支：\(branch)")
        }

        if !input.recentSubjects.isEmpty {
            let recent = input.recentSubjects.prefix(5).map { "- \($0)" }.joined(separator: "\n")
            sections.append("这个仓库最近的提交标题（请沿用同样的书写风格）：\n\(recent)")
        }

        if !input.stagedPaths.isEmpty {
            let paths = input.stagedPaths.prefix(50).map { "- \($0)" }.joined(separator: "\n")
            sections.append("本次暂存的文件：\n\(paths)")
        }

        // 如实告诉模型上下文不完整，它才不会对着残缺的 diff 编出完整的故事
        if !redacted.excludedPaths.isEmpty {
            let names = redacted.excludedPaths.joined(separator: "、")
            sections.append("注意：以下文件因涉及敏感内容未提供其改动详情：\(names)")
        }
        if !redacted.truncatedPaths.isEmpty {
            let names = redacted.truncatedPaths.joined(separator: "、")
            sections.append("注意：以下文件因改动过大未提供其改动详情：\(names)")
        }

        sections.append("改动内容：\n```diff\n\(redacted.text)\n```")

        return sections.joined(separator: "\n\n")
    }

    /// 收拾模型可能仍然带上的 markdown 围栏。
    ///
    /// 提示词已经说了不要加，但没有哪个模型是 100% 听话的，而围栏一旦漏进提交信息
    /// 就会留在仓库历史里洗不掉。这类后处理值得写。
    public static func sanitize(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeFirst()
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.removeLast()
        }

        if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            lines.removeFirst()
            if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                lines.removeLast()
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
