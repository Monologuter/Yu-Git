import SwiftUI

/// 空状态。
///
/// 替代系统的 `ContentUnavailableView`。后者有两个问题：
///
/// 一是**每个空状态长得一样**——一个灰色大图标加一行灰字，
/// 十几处空状态放在一起没有任何区别，看久了会觉得整个 app 是空的。
/// 这里把图标放进品牌色的圆底，那往往是一屏之内唯一的色块，
/// 认得出是驭Git，而不是「某个 macOS 应用」。
///
/// 二是它**只说现在什么都没有，不说下一步做什么**。所以说明句在这里不是可选的
/// 装饰：标题回答「现在是什么情况」，说明句回答「接下来该干嘛」。
/// 写不出说明句，通常意味着这个空状态本身就没想清楚。
struct EmptyStateView<Actions: View>: View {

    /// 空状态的语气。
    ///
    /// 只有两档，因为空状态只有两种性质：一种是正常的「这里暂时没东西」，
    /// 另一种是「有情况需要你处理」。再多分档，用户分辨不出差别。
    enum Tone {
        /// 常态。工作区干净、没有匹配结果、还没开始配置。
        case brand
        /// 需要注意。冲突未解、操作被中断。
        case warning
    }

    private let title: String
    private let systemImage: String
    private let description: String?
    private let tone: Tone
    private let isCompact: Bool
    private let actions: Actions

    init(
        _ title: String,
        systemImage: String,
        description: String? = nil,
        tone: Tone = .brand,
        compact: Bool = false,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.tone = tone
        self.isCompact = compact
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: isCompact ? Theme.Spacing.regular : Theme.Spacing.loose) {
            icon

            VStack(spacing: Theme.Spacing.tight) {
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Colors.primaryText)

                if let description {
                    Text(description)
                        .font(Theme.Font.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        // 说明句往往是两三行的完整句子。不封宽度的话它会铺满整个面板，
                        // 眼睛横扫太远，读起来反而比窄一点更累。
                        .frame(maxWidth: 260)
                        .fixedSize(horizontal: false, vertical: true)
                        // 说明句有时候装的是 git 或 AI 服务返回的原始报错。
                        // 那种文字用户多半要贴进搜索框或者发给别人，选不中就只能照着抄。
                        .textSelection(.enabled)
                }
            }

            actions
        }
        .padding(isCompact ? Theme.Spacing.section : Theme.Spacing.major)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: some View {
        let diameter: CGFloat = isCompact ? 36 : 48
        return Image(systemName: systemImage)
            .font(.system(size: isCompact ? 18 : 22))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
    }

    private var foreground: Color {
        switch tone {
        case .brand: Theme.Colors.brand
        case .warning: Theme.Colors.warning
        }
    }

    private var background: Color {
        switch tone {
        case .brand: Theme.Colors.brandWash
        case .warning: Theme.Colors.warningWash
        }
    }
}

extension EmptyStateView where Actions == EmptyView {

    /// 没有动作按钮的空状态。
    init(
        _ title: String,
        systemImage: String,
        description: String? = nil,
        tone: Tone = .brand,
        compact: Bool = false
    ) {
        self.init(
            title,
            systemImage: systemImage,
            description: description,
            tone: tone,
            compact: compact
        ) {
            EmptyView()
        }
    }
}
