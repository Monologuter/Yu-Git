import Foundation

/// 一块可以被分配到某个提交里的改动。
///
/// AIKit 不认识 `FileDiff`——它只依赖 Foundation，不依赖 GitKit。调用方负责把
/// diff 拆成这个形状，AIKit 只管「怎么分组」这件事。这条边界让 AIKit 可以脱离
/// 仓库单独测试，也免了两个包互相依赖。
public struct ComposableHunk: Sendable, Equatable, Identifiable {

    /// 稳定标识。AI 用它指认「这块归哪一组」，所以必须在一次会话里唯一且不变。
    public let id: String
    public let path: String
    /// `@@` 之后 git 给的定位提示，通常是所属函数名。
    public let heading: String
    /// 这一块的 diff 文本，交给模型看的就是它。
    public let patchText: String
    public let addedLines: Int
    public let deletedLines: Int

    public init(
        id: String,
        path: String,
        heading: String = "",
        patchText: String,
        addedLines: Int = 0,
        deletedLines: Int = 0
    ) {
        self.id = id
        self.path = path
        self.heading = heading
        self.patchText = patchText
        self.addedLines = addedLines
        self.deletedLines = deletedLines
    }
}

/// 一个提议出来的提交。
public struct ComposedCommit: Sendable, Equatable, Identifiable {

    public let id: UUID
    /// 提交标题。
    public var title: String
    /// 提交正文，可为空。
    public var body: String
    /// 为什么把这些改动归在一起。**只给用户看，不写进提交信息**——
    /// 用户要判断这个分组对不对，得知道 AI 是怎么想的。
    public var reason: String
    /// 归属这一组的改动块。
    public var hunkIDs: [String]
    /// 必须排在这一组之前的那几组。
    ///
    /// 用来把顺序排到「每个中间状态都能编译通过」——先加函数、再加调用它的地方。
    /// 顺序不对的话 bisect 会停在一堆根本编不过的提交上，整段历史等于白留。
    public var dependsOn: [UUID]

    public init(
        id: UUID = UUID(),
        title: String,
        body: String = "",
        reason: String = "",
        hunkIDs: [String],
        dependsOn: [UUID] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.reason = reason
        self.hunkIDs = hunkIDs
        self.dependsOn = dependsOn
    }

    /// 拼成最终的提交信息。
    public var message: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? title
            : "\(title)\n\n\(body)"
    }
}

/// 把一堆混在一起的改动按意图拆成若干个提交。
///
/// 支柱 2。要解决的是一个很具体的窘境：写代码时顺手改了三件事，提交时面对
/// `git add -p` 一块一块回答 y/n，还得自己记住哪块属于哪个主题。
/// 这里让模型先提议分组，用户再拖拽调整——**提议是草稿，分组权始终在用户手上**。
public struct CommitComposer: Sendable {

    /// 分组要通读所有改动并输出结构化结果，比写一条提交信息重得多。
    static let maxTokens = 16000

    private let provider: any AIProvider
    private let model: String

    public init(provider: any AIProvider, model: String) {
        self.provider = provider
        self.model = model
    }

    // MARK: - 提议

    public struct Proposal: Sendable, Equatable {
        /// 已按依赖排好序：被依赖的在前。
        public var commits: [ComposedCommit]
        /// 模型没有分配的改动。它们不会凭空消失——界面上单独列出来交给用户处理。
        public var unassignedHunkIDs: [String]
        /// 排序过程中值得告诉用户的事，比如依赖成环所以没能排。nil 表示排得干净。
        public var orderingNote: String?

        public init(
            commits: [ComposedCommit],
            unassignedHunkIDs: [String],
            orderingNote: String? = nil
        ) {
            self.commits = commits
            self.unassignedHunkIDs = unassignedHunkIDs
            self.orderingNote = orderingNote
        }
    }

    /// 请模型提议一份分组。
    public func propose(hunks: [ComposableHunk]) async throws -> Proposal {
        guard !hunks.isEmpty else {
            throw AIError.malformedResponse("没有可以分组的改动")
        }

        let request = AIRequest(
            model: model,
            system: Self.systemPrompt,
            messages: [.user(Self.userPrompt(hunks: hunks))],
            maxTokens: Self.maxTokens
        )

        let text = try await provider.complete(request)
        return try Self.parse(text, hunks: hunks)
    }

    // MARK: - 提示词

    static let systemPrompt = """
        你在帮一位中文用户把混在一起的代码改动，按「意图」拆成若干个提交。

        判断标准是**意图**而不是位置：同一个文件、甚至挨着的两处改动，如果做的是\
        两件事，就该分到两个提交；分散在五个文件里的改动如果服务于同一个目的，\
        就该合成一个。给你的改动块已经切到最细，相邻的两块完全可能属于不同提交。

        分组原则：
        - 一个提交只做一件事，能用一句话说清
        - 重构与功能改动分开；格式化、依赖升级这类噪音单独成组
        - 拿不准就少分几组——分得过细比分得过粗更烦人，用户还得手动合回去

        **顺序同样重要**：每个中间状态都要能编译通过，否则将来 bisect 会停在一堆\
        根本编不过的提交上，这段历史就白留了。所以定义排在使用之前、新增的字段\
        排在读取它的代码之前。用 dependsOn 说明「这一组必须排在哪几组后面」，\
        没有依赖就给空数组。不要为了凑顺序而制造依赖，只写真的存在的。

        提交信息用 Conventional Commits，描述用中文，标题不超过 50 个字符。

        只输出一个 JSON 对象，不要加 markdown 代码围栏，不要写任何解释。结构：

        {
          "commits": [
            {
              "key": "c1",
              "title": "feat(auth): 登录失败时自动重试",
              "body": "可省略。说明为什么这么改，不要复述 diff。",
              "reason": "给用户看的分组理由，一句话说清这些改动为什么归在一起",
              "dependsOn": ["c2"],
              "hunks": ["改动块的编号", "..."]
            }
          ]
        }

        key 是你给这一组起的短编号，只在 dependsOn 里互相指认时用。\
        每个改动块的编号必须**恰好出现一次**。宁可多分一组「其他改动」，\
        也不要遗漏任何一块。
        """

    static func userPrompt(hunks: [ComposableHunk]) -> String {
        var sections: [String] = []

        // 先给一份清单：模型分组时主要看这个，细看某一块时再往下翻
        let inventory = hunks.map { hunk in
            let location = hunk.heading.isEmpty ? hunk.path : "\(hunk.path) · \(hunk.heading)"
            return "- \(hunk.id)：\(location)（+\(hunk.addedLines) −\(hunk.deletedLines)）"
        }.joined(separator: "\n")

        sections.append("改动块清单（共 \(hunks.count) 块）：\n\(inventory)")

        let details = hunks.map { hunk in
            """
            ### \(hunk.id)
            文件：\(hunk.path)
            ```diff
            \(hunk.patchText)
            ```
            """
        }.joined(separator: "\n\n")

        sections.append("各块的具体内容：\n\n\(details)")
        sections.append("请把这 \(hunks.count) 块改动分组，输出 JSON。")

        return sections.joined(separator: "\n\n")
    }

    // MARK: - 解析

    /// 从模型输出里取出分组。
    ///
    /// 刻意**不用** Anthropic 的 structured outputs：那个参数在 OpenAI 兼容协议这边
    /// 没有统一对应物，很多第三方服务直接不认，用了就等于把 BYOK 的适用面砍掉一半。
    /// 提示词要求 JSON + 这里宽容解析，是能同时喂饱两家的唯一办法。
    static func parse(_ text: String, hunks: [ComposableHunk]) throws -> Proposal {
        guard let json = extractJSONObject(from: text) else {
            throw AIError.malformedResponse("模型没有返回 JSON：\(text.prefix(200))")
        }

        let decoded: RawProposal
        do {
            decoded = try JSONDecoder().decode(RawProposal.self, from: Data(json.utf8))
        } catch {
            throw AIError.malformedResponse("JSON 结构不符合预期：\(json.prefix(200))")
        }

        let validIDs = Set(hunks.map(\.id))
        var claimed = Set<String>()
        var commits: [ComposedCommit] = []
        /// 模型起的 key → 我们的 id。key 只在这一次回复里有效，不外传。
        var idsByKey: [String: UUID] = [:]
        var dependencyKeys: [UUID: [String]] = [:]

        for raw in decoded.commits {
            // 模型偶尔会编出不存在的编号，或者把同一块分给两组。
            // 两种都直接丢掉：一块改动只能进一个提交，重复应用会失败。
            let ids = raw.hunks.filter { validIDs.contains($0) && claimed.insert($0).inserted }
            guard !ids.isEmpty else { continue }

            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let commit = ComposedCommit(
                title: title,
                body: raw.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reason: raw.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                hunkIDs: ids
            )
            commits.append(commit)

            if let key = raw.key, !key.isEmpty {
                idsByKey[key] = commit.id
            }
            dependencyKeys[commit.id] = raw.dependsOn ?? []
        }

        // 漏掉的绝不能悄悄丢——那等于用户以为提交完了，实际还有改动留在工作区
        let unassigned = hunks.map(\.id).filter { !claimed.contains($0) }

        guard !commits.isEmpty else {
            throw AIError.malformedResponse("模型没有给出任何有效分组")
        }

        // key 换成 id。指向不存在的 key、指向自己的，一律丢掉——
        // 那是模型的笔误，留着只会让排序结果更奇怪。
        for index in commits.indices {
            let own = commits[index].id
            commits[index].dependsOn = (dependencyKeys[own] ?? [])
                .compactMap { idsByKey[$0] }
                .filter { $0 != own }
        }

        let ordered = order(commits)
        return Proposal(
            commits: ordered.commits,
            unassignedHunkIDs: unassigned,
            orderingNote: ordered.note
        )
    }

    // MARK: - 排序

    /// 按依赖拓扑排序，被依赖的排在前面。
    ///
    /// 同一批可选的里保持模型给的原始次序——排序只在必要时动手，
    /// 用户看到的顺序尽量贴近模型的表达，无谓的重排只会让人怀疑它在乱来。
    static func order(_ commits: [ComposedCommit]) -> (commits: [ComposedCommit], note: String?) {
        let positions = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($1.id, $0) })
        var remainingDependencies = commits.map { commit in
            // 指向已被丢弃的组的依赖不算数
            Set(commit.dependsOn.filter { positions[$0] != nil })
        }

        var placed: [ComposedCommit] = []
        var isPlaced = [Bool](repeating: false, count: commits.count)

        while placed.count < commits.count {
            // 取「依赖都已就位」的里面最靠前的那个
            guard
                let next = commits.indices.first(where: {
                    !isPlaced[$0] && remainingDependencies[$0].isEmpty
                })
            else { break }

            isPlaced[next] = true
            placed.append(commits[next])
            for index in commits.indices {
                remainingDependencies[index].remove(commits[next].id)
            }
        }

        guard placed.count == commits.count else {
            // 成环了。硬排一个顺序出来只是把问题藏起来，不如照原样给出并说明。
            let stuck = commits.indices.filter { !isPlaced[$0] }.map { commits[$0].title }
            return (
                commits,
                "这几组互相依赖，排不出「每一步都能编译」的顺序，已保留原始次序，请自行确认："
                    + stuck.joined(separator: "、")
            )
        }

        let reordered = placed.map(\.id) != commits.map(\.id)
        return (placed, reordered ? "已按依赖调整顺序：被依赖的改动排在前面" : nil)
    }

    /// 从一段可能带围栏、带前后废话的文本里抠出第一个完整的 JSON 对象。
    ///
    /// 按花括号配对扫描，而不是取第一个 `{` 到最后一个 `}`：模型有时会在 JSON
    /// 后面再补一句「以上是我的分组」，那样截会把尾巴也带进来。
    /// 扫描时跳过字符串字面量内部的括号——diff 内容里出现 `{` `}` 太常见了。
    static func extractJSONObject(from text: String) -> String? {
        let characters = Array(text)
        guard let start = characters.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var isEscaped = false

        for index in start..<characters.count {
            let character = characters[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if inString {
                if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(characters[start...index])
                }
            default: break
            }
        }

        return nil
    }

    private struct RawProposal: Decodable {
        let commits: [RawCommit]

        struct RawCommit: Decodable {
            let key: String?
            let title: String
            let body: String?
            let reason: String?
            let dependsOn: [String]?
            let hunks: [String]
        }
    }
}
