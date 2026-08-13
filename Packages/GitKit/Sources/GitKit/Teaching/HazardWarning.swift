import Foundation

/// 一次危险操作执行前该告诉用户的话。
///
/// 教学模式的核心。Git 让人怕的从来不是命令难打，而是**不知道按下去会发生什么、
/// 出事了能不能退回来**。所以每条预警固定回答三个问题：
/// 会发生什么、能不能撤销、怎么撤销。
public struct HazardWarning: Sendable, Equatable {

    /// 对话框标题。
    public let title: String
    /// 会发生什么——用具体的话说，不说「此操作有风险」这种废话。
    public let consequence: String
    /// 能不能退回来，以及怎么退。
    public let recovery: String
    /// 确认按钮上的字。写成动词短语而不是「确定」，
    /// 让人在点之前再读一遍自己要做什么。
    public let confirmLabel: String
    /// 等价的 git 命令，透明命令层照旧展示。
    public let equivalentCommand: String
    /// 是不是那种「按下去就找不回来」的操作，界面上用红色。
    public let isDestructive: Bool

    public init(
        title: String,
        consequence: String,
        recovery: String,
        confirmLabel: String,
        equivalentCommand: String,
        isDestructive: Bool
    ) {
        self.title = title
        self.consequence = consequence
        self.recovery = recovery
        self.confirmLabel = confirmLabel
        self.equivalentCommand = equivalentCommand
        self.isDestructive = isDestructive
    }
}

extension GitOperation {

    /// 这个操作需要预警吗。
    ///
    /// 安全操作不弹窗——把「暂存一个文件」也做成需要确认，只会让用户养成
    /// 闭眼点确定的习惯，等真正危险的那次也照点不误。
    public var needsWarning: Bool { hazard != .none }

    /// 生成执行前的预警。安全操作返回 nil。
    ///
    /// - Parameter hasSnapshot: 时间线是否会为这次操作留快照。
    ///   有快照时「怎么退回来」的答案完全不同——这正是驭Git 与其他客户端
    ///   最大的差别，值得在对话框里说清楚。
    public func warning(hasSnapshot: Bool) -> HazardWarning? {
        guard needsWarning else { return nil }

        switch hazard {
        case .none:
            return nil

        case .rewritesHistory:
            return HazardWarning(
                title: summary,
                consequence: "\(explanation)\n\n改写之后，这些提交会得到新的 commit hash。"
                    + "如果它们已经推送过，别人手上的版本会和你的对不上。",
                recovery: hasSnapshot
                    ? "驭Git 会先记下当前状态，随时可以从时间线退回来。"
                    : "原来的提交仍然留在 reflog 里，可以用 git reflog 找回，但需要手动操作。",
                confirmLabel: summary,
                equivalentCommand: equivalentCommand,
                isDestructive: false
            )

        case .discardsUncommittedWork:
            return HazardWarning(
                title: summary,
                // 这一类是唯一真正「找不回来」的：改动从未进过 git 的对象库
                consequence: "\(explanation)\n\n这些改动**从未提交过**，"
                    + "git 的对象库里没有它们的副本，reflog 也找不回来。",
                recovery: hasSnapshot
                    ? "驭Git 会在执行前拍一张工作区快照，从时间线可以完整恢复。"
                    : "没有任何退路。请确认这些改动确实不再需要。",
                confirmLabel: summary,
                equivalentCommand: equivalentCommand,
                isDestructive: true
            )
        }
    }
}

/// 新手引导里的一步。
///
/// 差异化设计里的「教学模式」。目标不是教会 Git 的全部概念，
/// 而是让第一次用的人知道**这个界面上哪里能做什么**。
public struct OnboardingStep: Sendable, Equatable, Identifiable {

    public let id: String
    public let title: String
    public let detail: String
    /// 对应的 git 概念，一句话解释。没有对应概念时为 nil。
    public let concept: String?

    public init(id: String, title: String, detail: String, concept: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.concept = concept
    }

    /// 打开一个仓库之后的引导路径。
    ///
    /// 顺序按**真实的工作流**排，而不是按 Git 的概念体系排：
    /// 先看改了什么，再挑要提交的，然后提交、推送。
    /// 概念解释挂在每一步旁边，用到时才讲。
    public static let repositoryTour: [OnboardingStep] = [
        OnboardingStep(
            id: "changes",
            title: "中间一栏是你改了什么",
            detail: "所有还没提交的改动都在这里。点一个文件，右边会显示具体改了哪几行。",
            concept: "「工作区」就是你正在编辑的这些文件本身。"
        ),
        OnboardingStep(
            id: "stage",
            title: "挑出这次要提交的部分",
            detail: "整个文件可以一键暂存；也可以在右边的 diff 上只暂存某一块、甚至某几行。",
            concept: "「暂存区」是一个中转站：先把想一起提交的改动放进去，再一次提交。"
                + "这让你可以把一次编辑拆成几个独立的提交。"
        ),
        OnboardingStep(
            id: "commit",
            title: "写一句话说清这次改了什么",
            detail: "在下面的框里写提交信息。配了 AI 的话可以让它先起个草稿，再自己改。",
            concept: "「提交」是一个存档点。存下之后随时能回到这一刻。"
        ),
        OnboardingStep(
            id: "history",
            title: "切到「历史」看走过的路",
            detail: "每一条都是一个存档点。右键某条提交可以直接合并、改写信息或丢弃它。",
            concept: "「分支」是同一份历史上的不同岔路，切换分支就是切换到另一条路上。"
        ),
        OnboardingStep(
            id: "timeline",
            title: "做错了从时间线退回来",
            detail: "危险操作执行前会自动留一个可恢复的时间点，⌘Z 能退回上一步之前。",
            concept: "这是驭Git 额外做的事：连「还没提交的改动被覆盖」也能找回来，"
                + "而这在 git 自己那里是做不到的。"
        ),
        OnboardingStep(
            id: "palette",
            title: "记不住在哪就按 ⌘K",
            detail: "命令面板列出当前能做的所有操作，每条旁边写着等价的 git 命令。",
            concept: "看多了那些命令，你就顺带把 Git 学会了。"
        ),
    ]
}
