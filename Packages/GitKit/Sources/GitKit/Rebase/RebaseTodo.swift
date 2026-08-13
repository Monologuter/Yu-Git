import Foundation

/// 一份 interactive rebase 的计划。
///
/// 对应 git 的 todo 文件，但**不直接暴露 git 的写法**：界面上用户拖动条目、
/// 从下拉里选动作，这个类型负责把那些意图翻译成 git 认得的 todo。
///
/// - Important: 条目顺序与 git 一致——**最旧的在前**。这和 `git log` 正好相反，
///   界面上要按需要翻转显示，但这个类型内部始终保持 git 的顺序，
///   免得在两种顺序之间来回转换时出错。
public struct RebaseTodo: Sendable, Equatable {

    /// 对单个 commit 要做的事。
    public enum Action: String, Sendable, Equatable, CaseIterable, Codable {
        /// 原样保留。
        case pick
        /// 保留改动，换一条提交信息。
        case reword
        /// 并进前一条，两条信息合起来。
        case squash
        /// 并进前一条，丢掉自己的信息。
        case fixup
        /// 整条丢弃。
        case drop

        public var displayName: String {
            switch self {
            case .pick: "保留"
            case .reword: "改写信息"
            case .squash: "合并到上一条"
            case .fixup: "合并到上一条（丢弃本条信息）"
            case .drop: "丢弃"
            }
        }

        /// 一句话讲清这个动作会发生什么。
        public var explanation: String {
            switch self {
            case .pick: "这条提交原样保留。"
            case .reword: "代码改动不变，只换一条新的提交信息。"
            case .squash: "把这条的改动并进上一条，两条的提交信息合起来。"
            case .fixup: "把这条的改动并进上一条，本条的提交信息丢掉。"
            case .drop: "整条提交连同它的改动一起去掉。后面的提交可能因此冲突。"
            }
        }

        /// 需要用户提供新的提交信息。
        public var needsMessage: Bool {
            self == .reword || self == .squash
        }
    }

    public struct Item: Sendable, Equatable, Identifiable {
        public var id: String { hash }

        public let hash: String
        /// 原本的提交标题，界面上显示用。
        public let originalSubject: String
        public var action: Action
        /// reword / squash 用的新提交信息。为空时沿用原来的。
        public var message: String?

        public init(hash: String, originalSubject: String, action: Action = .pick, message: String? = nil) {
            self.hash = hash
            self.originalSubject = originalSubject
            self.action = action
            self.message = message
        }
    }

    /// 变基的落点，通常是要整理的这批提交的父提交。
    public let base: String
    /// 待处理的提交，**最旧在前**。
    public var items: [Item]

    public init(base: String, items: [Item]) {
        self.base = base
        self.items = items
    }

    /// 从 `git log` 的结果建一份默认全 pick 的计划。
    ///
    /// - Parameter commits: `git log` 顺序（最新在前）的提交列表。
    public static func fromLogOrder(_ commits: [Commit], base: String) -> RebaseTodo {
        RebaseTodo(
            base: base,
            items: commits.reversed().map {
                Item(hash: $0.hash, originalSubject: $0.subject)
            }
        )
    }

    // MARK: - 校验

    /// 计划里说不通的地方。执行前必须为空。
    public enum Problem: Sendable, Equatable {
        /// 第一条不能是 squash / fixup——没有「上一条」可并。
        case leadingSquash
        /// 全部丢弃等于什么都不剩。
        case everythingDropped
        /// reword / squash 选了却没写新信息。
        case missingMessage(hash: String)

        public var localizedMessage: String {
            switch self {
            case .leadingSquash:
                "第一条提交没有「上一条」可以合并进去，请改成保留或调整顺序"
            case .everythingDropped:
                "所有提交都被丢弃了，这样不会剩下任何东西"
            case .missingMessage:
                "选了改写信息，但还没有填写新的提交信息"
            }
        }
    }

    public func validate() -> [Problem] {
        var problems: [Problem] = []

        let kept = items.filter { $0.action != .drop }
        if kept.isEmpty {
            problems.append(.everythingDropped)
        } else if kept[0].action == .squash || kept[0].action == .fixup {
            // 注意判断的是**丢弃之后**的第一条：把原来的第一条 drop 掉，
            // 第二条就变成了新的第一条，此时它若是 squash 同样无处可并。
            problems.append(.leadingSquash)
        }

        for item in items where item.action.needsMessage {
            if item.message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                problems.append(.missingMessage(hash: item.hash))
            }
        }

        return problems
    }

    /// 这份计划是否会改变任何东西。全是 pick 就没必要跑一趟 rebase。
    public var hasChanges: Bool {
        items.contains { $0.action != .pick }
    }

    // MARK: - 渲染成 git 的 todo

    /// 生成 todo 文件内容。
    ///
    /// reword 和 squash 不使用 git 自己的编辑器流程，而是翻译成
    /// `pick` + `exec git commit --amend --file=...`。原因很实在：
    /// 编辑器流程要求我们提供一个能被 git 反复调起、还要按顺序返回不同内容的程序，
    /// 既难写对也难测；而 `exec` 把「用哪条信息」在生成 todo 时就钉死了，
    /// 一眼能看明白，也能直接对着字符串写测试。
    ///
    /// - Parameter messageFile: 给定条目的提交信息文件路径。调用方负责把内容写进去。
    public func render(messageFile: (Item) -> String) -> String {
        var lines: [String] = []

        for item in items {
            switch item.action {
            case .pick:
                lines.append("pick \(item.hash) \(sanitize(item.originalSubject))")

            case .drop:
                // 写成 drop 而不是干脆省略：留着这一行，出问题时看 todo 就知道
                // 是我们有意丢的，而不是漏生成了
                lines.append("drop \(item.hash) \(sanitize(item.originalSubject))")

            case .reword:
                lines.append("pick \(item.hash) \(sanitize(item.originalSubject))")
                lines.append(amendCommand(file: messageFile(item)))

            case .fixup:
                lines.append("fixup \(item.hash) \(sanitize(item.originalSubject))")

            case .squash:
                // 用 fixup 而不是 squash：squash 会调起编辑器让人合并两条信息，
                // 而我们已经从界面上拿到了最终信息，直接 amend 更直接。
                lines.append("fixup \(item.hash) \(sanitize(item.originalSubject))")
                lines.append(amendCommand(file: messageFile(item)))
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func amendCommand(file: String) -> String {
        // --no-verify：git 自己在 rebase 重放提交时也不跑 pre-commit/commit-msg 钩子。
        // 跑了反而会因为「历史提交不符合今天的规则」而在半路失败。
        "exec git commit --amend --allow-empty --no-verify --file=\(shellQuote(file))"
    }

    /// 标题只是给人看的注释，但换行会把一行 todo 拆成两行，让 git 解析失败。
    private func sanitize(_ subject: String) -> String {
        subject
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// exec 行是交给 shell 跑的，路径必须引起来——仓库路径里有空格是常事。
    private func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
