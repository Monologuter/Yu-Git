import Foundation

/// 对某一条提交的一步到位操作。
///
/// 差异化设计里的 Quick Actions：用户想的是「把这条并回它父提交去」，
/// 而不是「打开 interactive rebase、找到这一行、把 pick 改成 fixup、保存退出」。
/// 这里把前者直接做成一个菜单项，rebase 计划由代码生成。
public enum QuickAction: Hashable, CaseIterable, Sendable {

    /// 并进父提交（更旧的那条），保留父提交的信息。
    ///
    /// 这是 git 原生的 `fixup` 方向，**不需要重排任何提交**。反过来做
    /// （并进更新的那条）就得把两条对调，而对调会让 git 把补丁按新顺序重放，
    /// 凭空引入本来不存在的冲突。
    case fixupIntoParent
    /// 只改这条的提交信息。
    case reword
    /// 丢掉这条。
    case drop

    public var title: String {
        switch self {
        case .fixupIntoParent: "合并进它的父提交"
        case .reword: "改写提交信息…"
        case .drop: "丢弃这条提交"
        }
    }

    public var systemImage: String {
        switch self {
        case .fixupIntoParent: "arrow.triangle.merge"
        case .reword: "pencil"
        case .drop: "trash"
        }
    }

    /// 一句话讲清会发生什么。
    public var explanation: String {
        switch self {
        case .fixupIntoParent: "这条的改动并进它的父提交，本条的提交信息丢掉。"
        case .reword: "代码改动不变，只换一条新的提交信息。"
        case .drop: "整条提交连同它的改动一起去掉。之后的提交可能因此冲突。"
        }
    }

    /// 需要先问用户要一段新的提交信息。
    public var needsMessage: Bool { self == .reword }

    /// 摘要，写进时间线。
    public func summary(subject: String) -> String {
        switch self {
        case .fixupIntoParent: "把「\(subject)」并进父提交"
        case .reword: "改写「\(subject)」的提交信息"
        case .drop: "丢弃「\(subject)」"
        }
    }

    /// 生成对应的 rebase 计划。
    ///
    /// - Parameters:
    ///   - target: 要动的那条提交。
    ///   - commits: `git log` 顺序（最新在前）的提交列表。
    ///   - message: reword 用的新信息。
    /// - Returns: 计划；条件不满足时返回 nil。
    public func makePlan(
        target: Commit,
        in commits: [Commit],
        message: String? = nil
    ) -> RebaseTodo? {
        guard let index = commits.firstIndex(where: { $0.hash == target.hash }) else { return nil }

        // 范围往回取到哪一条。往回取得越深，重放的提交越多，冲突和意外也越多，
        // 所以只取到必要的深度：
        // - fixup 要把 target 并进它的父提交，父提交得先被 pick 出来，所以要多带一条
        // - reword 和 drop 只动 target 自己，取到 target 就够
        //
        // 注意范围的另一头没得选：rebase 总是重放到 HEAD，比 target 更新的提交
        // 必然全在范围里。所以「只改一条」指的是只有一条被改标记，不是只重放一条。
        let depth = self == .fixupIntoParent ? index + 2 : index + 1
        guard depth <= commits.count else { return nil }

        let involved = Array(commits.prefix(depth))
        // base 用 HEAD~N 而不是具体 hash：根提交没有父提交，写 hash 会取不到
        var plan = RebaseTodo.fromLogOrder(involved, base: "HEAD~\(involved.count)")

        guard let position = plan.items.firstIndex(where: { $0.hash == target.hash }) else {
            return nil
        }

        switch self {
        case .fixupIntoParent:
            // 计划里最旧在前，fixup 是并进它前面那条——正好就是父提交，无需重排
            guard position > 0 else { return nil }
            plan.items[position].action = .fixup

        case .reword:
            plan.items[position].action = .reword
            plan.items[position].message = message

        case .drop:
            plan.items[position].action = .drop
        }

        return plan
    }

    /// 在给定位置上是否可用。
    ///
    /// - Parameters:
    ///   - index: target 在 `git log` 列表里的下标（0 是最新的一条）。
    ///   - loadedCount: 已经加载了多少条提交。
    public func isAvailable(at index: Int, loadedCount: Int) -> Bool {
        switch self {
        case .fixupIntoParent:
            // 需要父提交也在已加载范围内
            return index + 2 <= loadedCount
        case .reword, .drop:
            return index + 1 <= loadedCount
        }
    }
}
