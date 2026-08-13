import Foundation

/// 一条评审意见。
public struct ReviewFinding: Sendable, Equatable, Identifiable {

    /// 风险等级。决定排序和默认是否展开。
    public enum Severity: String, Sendable, Equatable, Codable, CaseIterable {
        /// 鉴权、权限、密钥、数据删改、并发安全——出错代价最高的那一类。
        case critical
        /// 可能出错的逻辑、边界条件、错误处理缺失。
        case warning
        /// 命名、结构、可读性。
        case info
        /// 纯格式化、空白、import 排序。默认折叠，别让它们淹没上面三类。
        case nitpick

        public var displayName: String {
            switch self {
            case .critical: "需要重点确认"
            case .warning: "可能有问题"
            case .info: "建议"
            case .nitpick: "小事"
            }
        }

        /// 排序权重，越小越靠前。
        ///
        /// 「鉴权/数据层置顶，格式化折叠」是 PRD 明确要求的导航方式：
        /// 一份 500 行的 diff 里最要紧的两处，不该和 30 条空格改动混在一起。
        public var order: Int {
            switch self {
            case .critical: 0
            case .warning: 1
            case .info: 2
            case .nitpick: 3
            }
        }

        /// 默认是否展开。
        public var isExpandedByDefault: Bool { self != .nitpick }
    }

    public let id: UUID
    public let severity: Severity
    public let path: String
    /// 新文件里的行号（1 起）。定位不到具体行时为 nil。
    public let line: Int?
    /// 一句话说清问题。
    public let title: String
    /// 展开后的详细说明。
    public let detail: String

    public init(
        id: UUID = UUID(),
        severity: Severity,
        path: String,
        line: Int? = nil,
        title: String,
        detail: String = ""
    ) {
        self.id = id
        self.severity = severity
        self.path = path
        self.line = line
        self.title = title
        self.detail = detail
    }
}

/// 一次评审的结果。
public struct DiffReview: Sendable, Equatable {

    /// 整份改动在做什么，中文两三句。
    public let summary: String
    /// 逐条意见，已按风险排序。
    public let findings: [ReviewFinding]
    /// 脱敏做了什么。界面上要如实展示——评审看的内容不完整时，结论也是不完整的。
    public let redaction: ContextRedactor.Result?

    public init(summary: String, findings: [ReviewFinding], redaction: ContextRedactor.Result? = nil) {
        self.summary = summary
        self.findings = findings
        self.redaction = redaction
    }

    public func findings(of severity: ReviewFinding.Severity) -> [ReviewFinding] {
        findings.filter { $0.severity == severity }
    }

    /// 有没有值得停下来看的东西。
    public var hasBlockingConcerns: Bool {
        findings.contains { $0.severity == .critical }
    }
}

/// 提交前的本地 diff 评审。
///
/// 支柱 4。定位是**提交前的自查**，不是替代 code review：它看不到需求文档、
/// 不知道团队约定，能做的是把「你可能没注意到的地方」指出来。
/// 所以输出永远是建议，从不阻断提交。
public struct DiffReviewer: Sendable {

    /// 评审要通读整份 diff 并逐条给意见，是所有 AI 任务里最重的一个。
    static let maxTokens = 16000

    private let provider: any AIProvider
    private let model: String
    private let redactor = ContextRedactor()

    public init(provider: any AIProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// 评审一份 diff。
    public func review(diff: String, branchName: String? = nil) async throws -> DiffReview {
        let redacted = redactor.redact(diff: diff)
        guard !redacted.text.isEmpty else {
            throw AIError.malformedResponse("没有可评审的内容")
        }

        let request = AIRequest(
            model: model,
            system: Self.systemPrompt,
            messages: [.user(Self.userPrompt(diff: redacted.text, branchName: branchName, redaction: redacted))],
            maxTokens: Self.maxTokens
        )

        let text = try await provider.complete(request)
        var review = try Self.parse(text)
        review = DiffReview(
            summary: review.summary,
            findings: review.findings,
            redaction: redacted.summary == nil ? nil : redacted
        )
        return review
    }

    // MARK: - 提示词

    static let systemPrompt = """
        你在帮一位中文用户做提交前的自查。你看到的只有这次改动的 diff，\
        看不到需求文档，也不知道团队约定——所以只指出**从代码本身能看出来**的问题，\
        不要猜测意图，也不要因为「可能不符合某种规范」而提意见。

        重点关注的顺序（这也是给意见定级的依据）：
        1. critical — 鉴权与权限判断、密钥与凭据、数据的删改与迁移、\
        并发与竞态、会丢数据或造成越权的逻辑
        2. warning — 边界条件、空值、错误被吞掉、资源没释放、明显的性能陷阱
        3. info — 命名、结构、可读性
        4. nitpick — 纯格式、空白、import 顺序

        宁缺毋滥：没有值得说的就不要凑数。一条意见对应一处具体位置，\
        不要写「整体来看建议重构」这种无法落地的话。

        只输出一个 JSON 对象，不要加 markdown 代码围栏，不要写任何解释。结构：

        {
          "summary": "两三句中文，说清这次改动做了什么",
          "findings": [
            {
              "severity": "critical | warning | info | nitpick",
              "path": "文件路径",
              "line": 42,
              "title": "一句话说清问题",
              "detail": "展开说明：为什么是问题，可以怎么改"
            }
          ]
        }

        line 是改动后文件里的行号，定位不到就省略这个字段。findings 可以是空数组。
        """

    static func userPrompt(
        diff: String,
        branchName: String?,
        redaction: ContextRedactor.Result
    ) -> String {
        var sections: [String] = []

        if let branchName {
            sections.append("分支：\(branchName)")
        }

        // 上下文不完整时如实说明，否则模型会对着残缺内容给出笃定的结论
        if !redaction.excludedPaths.isEmpty {
            sections.append("注意：以下文件因涉及敏感内容未提供：\(redaction.excludedPaths.joined(separator: "、"))")
        }
        if !redaction.truncatedPaths.isEmpty {
            sections.append("注意：以下文件因改动过大未提供：\(redaction.truncatedPaths.joined(separator: "、"))")
        }

        sections.append("改动内容：\n```diff\n\(diff)\n```")
        sections.append("请评审，输出 JSON。")

        return sections.joined(separator: "\n\n")
    }

    // MARK: - 解析

    static func parse(_ text: String) throws -> DiffReview {
        guard let json = CommitComposer.extractJSONObject(from: text) else {
            throw AIError.malformedResponse("模型没有返回 JSON：\(text.prefix(200))")
        }

        let raw: RawReview
        do {
            raw = try JSONDecoder().decode(RawReview.self, from: Data(json.utf8))
        } catch {
            throw AIError.malformedResponse("JSON 结构不符合预期：\(json.prefix(200))")
        }

        let findings = (raw.findings ?? []).compactMap { item -> ReviewFinding? in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }

            return ReviewFinding(
                // 认不出的等级按 info 算：既不会被当成紧急问题，也不会被折叠掉看不见
                severity: item.severity.flatMap(ReviewFinding.Severity.init(rawValue:)) ?? .info,
                path: item.path ?? "",
                // 行号为 0 或负数是模型算错了，当作定位不到
                line: item.line.flatMap { $0 > 0 ? $0 : nil },
                title: title,
                detail: item.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        // 稳定排序：同级内保持模型给的顺序，它通常按文件顺序走
        .enumerated()
        .sorted { ($0.element.severity.order, $0.offset) < ($1.element.severity.order, $1.offset) }
        .map(\.element)

        let summary = raw.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !summary.isEmpty || !findings.isEmpty else {
            throw AIError.malformedResponse("模型没有给出任何评审结果")
        }

        return DiffReview(summary: summary, findings: findings)
    }

    private struct RawReview: Decodable {
        let summary: String?
        let findings: [RawFinding]?

        struct RawFinding: Decodable {
            let severity: String?
            let path: String?
            let line: Int?
            let title: String
            let detail: String?
        }
    }
}
