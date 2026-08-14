import GitKit
import SwiftUI

/// 在提交列表上右键某一条能做的事。
///
/// 和 ``QuickAction`` 分开是因为两者的实现路径完全不同：Quick Action 生成一份
/// rebase 计划再重放，这里的每一项都是一条直接的 git 命令。混在一起的话，
/// 「这一步会不会重放我后面的提交」这个关键区别就没地方体现了。
enum CommitAction: Hashable, CaseIterable, Identifiable {

    /// 把这条提交的改动重放到当前分支。
    case cherryPick
    /// 生成反向提交抵消这一条。
    case revert
    /// 分支指针退到这条提交，改动全留在暂存区。
    case resetSoft
    /// 分支指针退到这条提交，改动退回未暂存。
    case resetMixed
    /// 分支指针退到这条提交，并清掉未提交的改动。
    case resetHard
    /// 在这条提交上打标签。
    case tag

    var id: Self { self }

    var title: String {
        switch self {
        case .cherryPick: "挑取到当前分支"
        case .revert: "撤销这条提交…"
        case .resetSoft: "软重置到这里（改动留在暂存区）…"
        case .resetMixed: "混合重置到这里（改动退回未暂存）…"
        case .resetHard: "硬重置到这里（丢弃未提交的改动）…"
        case .tag: "在这里打标签…"
        }
    }

    var systemImage: String {
        switch self {
        case .cherryPick: "arrow.turn.up.right"
        case .revert: "arrow.uturn.backward"
        case .resetSoft, .resetMixed, .resetHard: "arrow.left.to.line"
        case .tag: "tag"
        }
    }

    /// 一句话讲清会发生什么。菜单项的 tooltip 用它。
    var explanation: String {
        switch self {
        case .cherryPick:
            "把这条提交的改动重放到当前分支，生成一条新提交。原提交仍留在它自己的分支上。"
        case .revert:
            "生成一条新提交，内容是这一条的反向改动。原提交仍在历史里——"
                + "已经推送给别人的提交只能这样撤销。"
        case .resetSoft:
            "当前分支退到这条提交，被跳过的改动全部留在暂存区，可以重新组织成新的提交。"
        case .resetMixed:
            "当前分支退到这条提交，被跳过的改动退回未暂存状态，工作区里的文件内容不变。"
        case .resetHard:
            "当前分支退到这条提交，并用它的内容覆盖暂存区和工作区。"
                + "所有未提交的改动都会消失，未跟踪的文件不受影响。"
        case .tag:
            "在这条提交上打一个标签。填了说明就是附注标签，发版要用那种。"
        }
    }

    /// 分组：菜单里同组的排在一起，组间加分隔线。
    ///
    /// 分组不是为了整齐，是为了让「往历史上加东西」和「把指针往回挪」
    /// 在视觉上就分开——它们的后果完全不是一回事。
    var group: Int {
        switch self {
        case .cherryPick, .revert: 0
        case .resetSoft, .resetMixed, .resetHard: 1
        case .tag: 2
        }
    }

    /// 这一项要不要先确认。
    ///
    /// cherry-pick 是唯一不用问的：它只往历史上加一条新提交，
    /// 后悔了删掉就行。多问一次只会让人养成闭眼点确定的习惯。
    var needsConfirmation: Bool { self != .cherryPick }

    /// 对应的操作。`tag` 不在这里——它还要先问用户要个名字。
    func operation(for commit: Commit) -> GitOperation? {
        switch self {
        case .cherryPick: .cherryPick(hash: commit.hash, subject: commit.subject)
        case .revert: .revert(hash: commit.hash, subject: commit.subject)
        case .resetSoft: .resetSoft(to: commit.hash)
        case .resetMixed: .resetMixed(to: commit.hash)
        case .resetHard: .resetHard(to: commit.hash)
        case .tag: nil
        }
    }

    /// 执行前需要确认这条提交在当前分支的历史里。
    ///
    /// 「重置到这里」这句话默认的意思是「退回到我走过的某个点」。如果目标不在
    /// 当前分支上，实际发生的是把分支整个搬到另一段历史上去——那是完全不同的一件事，
    /// 不该藏在「重置」这个词后面。
    ///
    /// 历史列表用的是 `--all`，屏幕上确实会同时出现别的分支的提交，
    /// 所以这个校验不是理论上的。判断要跑 `merge-base --is-ancestor`，
    /// 而右键菜单是同步构建的——所以放在执行前查，不在菜单里灰掉。
    var requiresAncestorOfHead: Bool {
        switch self {
        case .resetSoft, .resetMixed, .resetHard: true
        case .cherryPick, .revert, .tag: false
        }
    }
}
