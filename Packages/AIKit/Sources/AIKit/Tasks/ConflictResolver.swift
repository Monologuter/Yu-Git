import Foundation

/// 一处待解决的冲突，交给模型看的形状。
public struct ConflictContext: Sendable, Equatable {

    public let path: String
    /// 在文件里的第几处（0 起）。
    public let index: Int
    /// 我方的内容。
    public let ours: [String]
    /// 对方的内容。
    public let theirs: [String]
    /// 共同祖先。为空时模型只能在两个结果间猜，置信度会明显下降。
    public let base: [String]?
    /// 冲突块前后各若干行，用于判断这段代码在做什么。
    public let contextBefore: [String]
    public let contextAfter: [String]

    public init(
        path: String,
        index: Int,
        ours: [String],
        theirs: [String],
        base: [String]?,
        contextBefore: [String] = [],
        contextAfter: [String] = []
    ) {
        self.path = path
        self.index = index
        self.ours = ours
        self.theirs = theirs
        self.base = base
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
    }
}

/// 模型给出的一处解决建议。
public struct ConflictSuggestion: Sendable, Equatable {

    /// 模型有多大把握。
    public enum Confidence: String, Sendable, Equatable, Codable {
        /// 双方改的是同一处的不同写法，或一方只是格式调整——机械可判。
        case high
        /// 能看出意图，但合并方式有多种合理选择。
        case medium
        /// 双方改的是同一段逻辑且意图冲突，需要人来定夺。
        case low

        public var displayName: String {
            switch self {
            case .high: "把握较大"
            case .medium: "仅供参考"
            case .low: "建议人工确认"
            }
        }

        /// 高置信度也**不自动应用**。这是 AI 铁律：AI 提议，用户拍板。
        /// 色标只是帮用户决定「哪几处可以快速扫过、哪几处要停下来细看」。
        public var sortWeight: Int {
            switch self {
            case .low: 0
            case .medium: 1
            case .high: 2
            }
        }
    }

    /// 建议的最终内容。
    public let resolvedLines: [String]
    /// 中文理由：为什么这么合。
    public let reason: String
    public let confidence: Confidence

    public init(resolvedLines: [String], reason: String, confidence: Confidence) {
        self.resolvedLines = resolvedLines
        self.reason = reason
        self.confidence = confidence
    }
}

/// 逐处给出冲突解决建议。
///
/// 支柱 4。终端里解冲突最难的不是操作，而是**看不懂对方为什么这么改**——
/// 于是要么全要自己的，要么全要对方的，两种都会丢东西。
/// 这里让模型把「双方各自改了什么、合起来该是什么样」讲成中文。
public struct ConflictResolver: Sendable {

    /// 一处冲突的建议不长，但解释要说清楚，给宽一点。
    static let maxTokens = 8192

    private let provider: any AIProvider
    private let model: String

    public init(provider: any AIProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    /// 请模型给一处冲突出建议。
    public func suggest(for conflict: ConflictContext) async throws -> ConflictSuggestion {
        let request = AIRequest(
            model: model,
            system: Self.systemPrompt,
            messages: [.user(Self.userPrompt(conflict))],
            maxTokens: Self.maxTokens
        )

        let text = try await provider.complete(request)
        return try Self.parse(text)
    }

    // MARK: - 提示词

    static let systemPrompt = """
        你在帮一位中文用户解决 Git 合并冲突。

        每次给你一处冲突，包含：共同祖先（base）、我方改动（ours）、对方改动（theirs），\
        以及前后若干行上下文。

        先判断双方**各自**在共同祖先的基础上改了什么，再决定合起来应该是什么样：
        - 两边改的是不相干的部分 → 都保留
        - 一边只是格式化、改名，另一边是真逻辑改动 → 以逻辑改动为准，套上新格式
        - 两边实现了同一个意图的不同写法 → 选更完整或更安全的那个，并说明理由
        - 两边意图直接矛盾 → 不要硬合，置信度给 low，说清矛盾在哪，让人来定

        没有给出共同祖先时，你只能在两个结果之间猜，置信度不要高于 medium。

        只输出一个 JSON 对象，不要加 markdown 代码围栏，不要写任何解释。结构：

        {
          "resolved": ["合并后的第一行", "第二行"],
          "reason": "中文说明：双方各改了什么，为什么这么合",
          "confidence": "high | medium | low"
        }

        resolved 是**逐行**的数组，不要包含任何冲突标记，不要带行号，\
        缩进原样保留。整块都该删掉时给空数组。
        """

    static func userPrompt(_ conflict: ConflictContext) -> String {
        var sections: [String] = ["文件：\(conflict.path)"]

        if !conflict.contextBefore.isEmpty {
            sections.append("冲突之前的内容：\n```\n\(conflict.contextBefore.joined(separator: "\n"))\n```")
        }

        if let base = conflict.base {
            sections.append("共同祖先（base）：\n```\n\(base.joined(separator: "\n"))\n```")
        } else {
            sections.append("（这次没有共同祖先可参考）")
        }

        sections.append("我方改动（ours）：\n```\n\(conflict.ours.joined(separator: "\n"))\n```")
        sections.append("对方改动（theirs）：\n```\n\(conflict.theirs.joined(separator: "\n"))\n```")

        if !conflict.contextAfter.isEmpty {
            sections.append("冲突之后的内容：\n```\n\(conflict.contextAfter.joined(separator: "\n"))\n```")
        }

        sections.append("请给出合并建议，输出 JSON。")
        return sections.joined(separator: "\n\n")
    }

    // MARK: - 解析

    static func parse(_ text: String) throws -> ConflictSuggestion {
        // 抠 JSON 的规则与 CommitComposer 完全一致，共用一份实现
        guard let json = CommitComposer.extractJSONObject(from: text) else {
            throw AIError.malformedResponse("模型没有返回 JSON：\(text.prefix(200))")
        }

        let raw: RawSuggestion
        do {
            raw = try JSONDecoder().decode(RawSuggestion.self, from: Data(json.utf8))
        } catch {
            throw AIError.malformedResponse("JSON 结构不符合预期：\(json.prefix(200))")
        }

        // 模型偶尔会把冲突标记原样抄进结果里。那样写回去等于什么都没解决，
        // 而且 git add 不会拦，会一路提交出去。
        let hasMarkers = raw.resolved.contains { line in
            line.hasPrefix("<<<<<<<") || line.hasPrefix("=======") || line.hasPrefix(">>>>>>>")
                || line.hasPrefix("|||||||")
        }
        guard !hasMarkers else {
            throw AIError.malformedResponse("建议里仍然带着冲突标记")
        }

        return ConflictSuggestion(
            resolvedLines: raw.resolved,
            reason: raw.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            // 认不出的置信度一律按最低算——宁可让用户多看一眼
            confidence: raw.confidence.flatMap(ConflictSuggestion.Confidence.init(rawValue:)) ?? .low
        )
    }

    private struct RawSuggestion: Decodable {
        let resolved: [String]
        let reason: String?
        let confidence: String?
    }
}
