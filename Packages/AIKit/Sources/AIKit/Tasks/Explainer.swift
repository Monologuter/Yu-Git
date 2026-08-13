import Foundation

/// 用中文讲清楚一段 commit、一份 diff、一个分支到底发生了什么。
///
/// 对应差异化设计里的「界面即中文 Git 教材」：不是把英文术语翻成中文，
/// 而是把「这一步对我的代码做了什么」讲明白。
public struct Explainer: Sendable {

    /// 解释类任务输出较长，且部分模型的 `max_tokens` 是「思考 + 正文」的总上限，
    /// 给足预算避免正文说到一半被截断。
    static let maxTokens = 8192

    private let provider: any AIProvider
    private let model: String
    private let redactor = ContextRedactor()

    public init(provider: any AIProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// 要解释的对象。
    public enum Subject: Sendable {
        /// 一次提交：标题、作者、改动。
        case commit(subject: String, author: String, date: String, diff: String)
        /// 一份改动（工作区或暂存区）。
        case diff(String)
        /// 一个分支相对于基线分支的差异。
        case branch(name: String, baseName: String, commitSubjects: [String], diffStat: String)
    }

    public struct Stream: Sendable {
        public let redaction: ContextRedactor.Result?
        public let text: AsyncThrowingStream<String, any Error>
    }

    public func explain(_ subject: Subject) -> Stream {
        let (prompt, redaction) = buildPrompt(for: subject)

        let request = AIRequest(
            model: model,
            system: Self.systemPrompt,
            messages: [.user(prompt)],
            maxTokens: Self.maxTokens
        )

        let stream = provider.stream(request)
        return Stream(
            redaction: redaction,
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
        你在帮一位中文用户读懂 Git 仓库里发生的事。用户是开发者，看得懂代码，\
        但不一定熟悉 Git 的术语和这个仓库的历史。

        写作要求：
        - 全程用中文。Git 术语（commit、rebase、merge、HEAD 等）保留英文原词，不要翻译
        - 先说结论：第一句就回答「这做了什么」，细节放后面
        - 讲清「为什么」和「影响了什么」，不要逐行复述代码——用户自己能看代码
        - 篇幅克制。简单改动两三句话说完，复杂的才展开
        - 不确定的地方明说不确定，不要编造动机或背景
        - 不要用「本次提交」「该改动」这类空话开头，直接说事
        """

    private func buildPrompt(for subject: Subject) -> (String, ContextRedactor.Result?) {
        switch subject {
        case let .commit(commitSubject, author, date, diff):
            let redacted = redactor.redact(diff: diff)
            let prompt = """
                解释这次 commit 做了什么。

                标题：\(commitSubject)
                作者：\(author)
                时间：\(date)
                \(Self.redactionNotice(redacted))
                改动内容：
                ```diff
                \(redacted.text)
                ```
                """
            return (prompt, redacted)

        case let .diff(diff):
            let redacted = redactor.redact(diff: diff)
            let prompt = """
                解释这份改动做了什么，以及它可能带来什么影响。
                \(Self.redactionNotice(redacted))
                改动内容：
                ```diff
                \(redacted.text)
                ```
                """
            return (prompt, redacted)

        case let .branch(name, baseName, commitSubjects, diffStat):
            let subjects = commitSubjects.prefix(30).map { "- \($0)" }.joined(separator: "\n")
            let prompt = """
                用几句话说清分支 `\(name)` 相对 `\(baseName)` 做了什么，\
                以及合并它需要注意什么。

                这些 commit 只在 `\(name)` 上：
                \(subjects.isEmpty ? "（没有独有的 commit）" : subjects)

                改动统计：
                ```
                \(diffStat)
                ```
                """
            return (prompt, nil)
        }
    }

    /// 上下文被删改过就如实告诉模型，免得它对着残缺内容编出完整故事。
    private static func redactionNotice(_ result: ContextRedactor.Result) -> String {
        var notes: [String] = []
        if !result.excludedPaths.isEmpty {
            notes.append("以下文件因涉及敏感内容未提供改动详情：\(result.excludedPaths.joined(separator: "、"))")
        }
        if !result.truncatedPaths.isEmpty {
            notes.append("以下文件因改动过大未提供改动详情：\(result.truncatedPaths.joined(separator: "、"))")
        }
        guard !notes.isEmpty else { return "" }
        return "\n注意：" + notes.joined(separator: "；") + "\n"
    }
}
