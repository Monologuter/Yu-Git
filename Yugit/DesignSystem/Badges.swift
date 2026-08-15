import GitKit
import SwiftUI

// 设计系统 `components/badges/` 那一组的 Swift 对应。
//
// 单独成层而不是每处内联：徽章出现在侧栏、历史列表、详情面板三处，
// 内联的话同一个「远程分支」在三处会长成三个样子——这已经发生过，
// 本地分支的徽章一度用的是系统强调色，而设计稿要的是品牌靛。

/// 计数胶囊。跟在标题后面说明「有几个」，不参与点击。
struct CountPill: View {

    enum Tone {
        case neutral
        case warning
    }

    private let count: Int
    private let tone: Tone

    init(_ count: Int, tone: Tone = .neutral) {
        self.count = count
        self.tone = tone
    }

    var body: some View {
        Text("\(count)")
            .font(Theme.Font.secondary)
            // 等宽数字：不然计数从 9 变到 10 时整个胶囊会跳一下
            .monospacedDigit()
            .foregroundStyle(tone == .warning ? Theme.Colors.warning : Theme.Colors.secondaryText)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .frame(minWidth: 16)
            .background(
                tone == .warning ? Theme.Colors.warningWash : Theme.Colors.fillQuaternary,
                in: .capsule
            )
    }
}

/// commit 上的分支 / tag 徽章。
struct RefBadge: View {

    enum Kind {
        case localBranch
        case remoteBranch
        case tag

        /// 三种引用各自的颜色。
        ///
        /// 本地分支用**品牌靛**而不是系统强调色：强调色归选中态，
        /// 而选中一行提交时它的徽章就画在强调色背景上——两者同色等于徽章消失。
        @MainActor var tint: Color {
            switch self {
            case .localBranch: Theme.Colors.brand
            case .remoteBranch: Theme.Colors.secondaryText
            case .tag: Theme.Colors.warning
            }
        }
    }

    let kind: Kind
    let name: String
    /// 所在的行是不是选中态。
    var isEmphasized = false

    var body: some View {
        Text(name)
            .font(Theme.Font.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            // 封 170pt：一个 `origin/feature/very-long-branch-name` 不封宽度
            // 会把提交标题整个挤出去，而标题才是这一行存在的理由
            .frame(maxWidth: 170)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(isEmphasized ? Theme.Colors.onAccent : kind.tint)
            .background(
                (isEmphasized ? Theme.Colors.onAccent : kind.tint).opacity(
                    isEmphasized ? 0.22 : 0.15),
                in: .capsule
            )
    }
}

/// 一条提交上的全部引用徽章。
struct RefBadges: View {

    let refs: [CommitRef]
    var isEmphasized = false

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            ForEach(Array(refs.enumerated()), id: \.offset) { _, ref in
                if let badge = badge(for: ref) {
                    RefBadge(kind: badge.kind, name: badge.name, isEmphasized: isEmphasized)
                }
            }
        }
    }

    private func badge(for ref: CommitRef) -> (kind: RefBadge.Kind, name: String)? {
        switch ref {
        // HEAD 总是和它指向的分支一起出现，单独画一个徽章只是噪音
        case .head: nil
        case let .localBranch(name): (.localBranch, name)
        case let .remoteBranch(name): (.remoteBranch, name)
        case let .tag(name): (.tag, name)
        case .other: nil
        }
    }
}

/// 分支的 ahead / behind 指示。
struct TrackingBadge: View {

    let tracking: TrackingStatus
    var isEmphasized = false

    var body: some View {
        // upstream 被删了单独警示——那会让 push 直接失败，
        // 而它和「领先几条」不是一个量级的信息
        if tracking.isGone {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(isEmphasized ? Theme.Colors.onAccent : Theme.Colors.warning)
                .help("upstream 已在远程被删除")
        } else if tracking.ahead > 0 || tracking.behind > 0 {
            HStack(spacing: 5) {
                if tracking.ahead > 0 {
                    directionCount("arrow.up", tracking.ahead)
                }
                if tracking.behind > 0 {
                    directionCount("arrow.down", tracking.behind)
                }
            }
            .font(Theme.Font.secondary)
            .monospacedDigit()
            .foregroundStyle(isEmphasized ? Theme.Colors.onAccent : Theme.Colors.secondaryText)
            .help("领先 \(tracking.ahead)，落后 \(tracking.behind)")
        }
    }

    private func directionCount(_ symbol: String, _ value: Int) -> some View {
        HStack(spacing: 1) {
            Image(systemName: symbol)
                .font(.system(size: 9))
            Text("\(value)")
        }
    }
}

/// 文件状态字母。
///
/// 等宽 + 固定 14pt 宽，好让后面的路径左边界对齐成一列。不固定的话
/// A/M/D 各自宽度不同，整列会呈锯齿状。
///
/// **状态永远同时由字母和颜色表达**——只靠颜色的话色盲用户什么都读不到，
/// 而这一列传的是「这个文件被怎么了」，读不到就等于这一列不存在。
struct StatusLetter: View {

    let entry: StatusEntry
    var showsIndexStatus = false
    var isEmphasized = false

    var body: some View {
        Text(letter)
            .font(Theme.Font.mono)
            .foregroundStyle(isEmphasized ? Theme.Colors.onAccent : tint)
            .frame(width: 14)
            .help(explanation)
    }

    private var status: FileStatus {
        showsIndexStatus ? entry.indexStatus : entry.workTreeStatus
    }

    private var letter: String {
        switch entry.kind {
        case .untracked: "?"
        case .unmerged: "!"
        case .ignored: "·"
        case .renamed: "R"
        case .copied: "C"
        case .ordinary: String(status.rawValue)
        }
    }

    private var tint: Color {
        switch entry.kind {
        case .untracked: Theme.Colors.secondaryText
        case .unmerged: Theme.Colors.warning
        case .ignored: Theme.Colors.decorativeText
        // 改名和复制归到合并色：它们和新增/删除不是一回事，
        // 内容其实没变，变的是这个文件在树里的位置
        case .renamed, .copied: Theme.Colors.mergeAccent
        case .ordinary:
            switch status {
            case .added: Theme.Colors.success
            case .deleted: Theme.Colors.danger
            case .modified, .fileTypeChanged: Theme.Colors.accent
            default: Theme.Colors.secondaryText
            }
        }
    }

    private var explanation: String {
        switch entry.kind {
        case .untracked: "未跟踪"
        case .unmerged: "有冲突"
        case .ignored: "已忽略"
        case .renamed: "改名"
        case .copied: "复制"
        case .ordinary:
            switch status {
            case .added: "新增"
            case .deleted: "删除"
            case .modified: "修改"
            case .fileTypeChanged: "类型变化"
            default: "未改动"
            }
        }
    }
}
