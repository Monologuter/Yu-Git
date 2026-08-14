import AppKit
import SwiftUI

/// 一套主题必须提供的全部颜色。
///
/// 这个协议就是「主题」的定义：实现它就等于做出了一套主题，
/// 而所有界面代码只跟 ``Theme/Colors`` 打交道，不认识具体是哪套。
///
/// 分成五组不是为了整齐，是因为它们的**约束彼此冲突**，必须分开想：
/// - 界面色要退到背景里去，让内容站出来
/// - 品牌色要有辨识度，但只能出现在少数几处，多了就成噪音
/// - 分支图 8 色要等明度、互相拉开，还得避开红绿
/// - diff 色被红绿语义锁死，且需要两层可叠加的背景
/// - 语法色要在 diff 的底色之上仍然可读
///
/// 一套配色在某一组上做得好，往往正是它在另一组上出问题的原因——
/// 比如高饱和的分支图色板画在低对比的暖色背景上会刺眼。
/// 所以每组都要单独验，不能只看色卡好不好看。
@MainActor
protocol ThemePalette: Sendable {

    /// 持久化用的稳定标识，改了会让用户的选择丢失。
    var identifier: String { get }
    /// 设置界面里显示的名字。
    var displayName: String { get }
    /// 一句话说明它适合谁，显示在设置页的选项下方。
    var summary: String { get }

    /// 是否直接沿用系统颜色。
    ///
    /// 为 true 时界面完全跟随 macOS 的强调色设置与深浅模式，
    /// 这是「默认」主题的做法，也是最不容易出错的一套。
    var followsSystemAppearance: Bool { get }

    // MARK: - 品牌

    /// 主色。用于当前分支标记、主按钮、选中态。
    var accent: Color { get }
    /// 画在主色背景上的前景色。
    ///
    /// 单独给一个而不是固定用白色：低对比主题的主色可能很浅，
    /// 白字压不住。
    var onAccent: Color { get }

    // MARK: - 界面

    var contentBackground: Color { get }
    var primaryText: Color { get }
    var secondaryText: Color { get }
    var tertiaryText: Color { get }
    var separator: Color { get }

    // MARK: - 分支图
    //
    // 用 NSColor 而不是 Color：绘制发生在 AppKit 的 `NSBezierPath` 里，
    // 每帧都要 setStroke()，转换一次是一次开销。

    /// 8 条轨道的配色。
    var lanes: [NSColor] { get }
    /// 行被选中且窗口活跃时，轨道与节点改用的颜色。
    ///
    /// 不给这个的话，蓝色的轨道画在蓝色选中背景上会消失——
    /// 这不是假设，是真实发生过的 bug。
    var laneOnSelection: NSColor { get }
    /// 节点中心挖空处的填充色（未选中时）。
    var laneNodeCore: NSColor { get }
    /// 节点中心挖空处的填充色（选中时）。挖成白色会在深色选中背景上留一个刺眼的洞。
    var laneNodeCoreOnSelection: NSColor { get }

    /// 轨道曲线的线宽。
    ///
    /// 放进主题而不是写死：这个值对「好不好看」的影响超过其他所有参数，
    /// 而不同配色需要的粗细并不一样——低饱和的色板需要更粗才撑得住。
    var laneLineWidth: CGFloat { get }
    /// 提交节点的半径。
    var laneNodeRadius: CGFloat { get }

    // MARK: - diff

    var diffAddedText: Color { get }
    var diffDeletedText: Color { get }
    /// 整行底色。
    var diffAddedLine: Color { get }
    var diffDeletedLine: Color { get }
    /// 词级变化处的底色，会**叠加**在整行底色之上。
    ///
    /// 两层叠起来之后代码文字仍须清晰可读——这是配色最容易翻车的地方，
    /// 定完必须实际叠一次看，不能只看单色的对比度。
    var diffAddedWord: Color { get }
    var diffDeletedWord: Color { get }
    /// 冲突标记。
    var conflict: Color { get }
    /// 危险操作。
    var danger: Color { get }

    // MARK: - 语法高亮

    var syntaxKeyword: Color { get }
    var syntaxString: Color { get }
    var syntaxComment: Color { get }
    var syntaxNumber: Color { get }
    var syntaxType: Color { get }
}

// MARK: - 默认实现

/// 默认主题：完全跟随系统。
///
/// 它的价值在于**不出错**：跟随用户在系统设置里选的强调色、
/// 自动适配深浅模式、自动响应「增强对比度」辅助功能。
/// 自定义主题要自己维护这三件事，而这一套白拿。
///
/// 代价是没有辨识度——截图里认不出这是驭Git。所以它是安全的默认，
/// 不是唯一的选择。
struct SystemTheme: ThemePalette {

    let identifier = "system"
    let displayName = "默认"
    let summary = "跟随系统外观与强调色，最接近原生 macOS 应用"
    let followsSystemAppearance = true

    var accent: Color { .accentColor }
    var onAccent: Color { Color(nsColor: .alternateSelectedControlTextColor) }

    var contentBackground: Color { Color(nsColor: .textBackgroundColor) }
    var primaryText: Color { Color(nsColor: .labelColor) }
    var secondaryText: Color { Color(nsColor: .secondaryLabelColor) }
    var tertiaryText: Color { Color(nsColor: .tertiaryLabelColor) }
    var separator: Color { Color(nsColor: .separatorColor) }

    /// 刻意避开红绿——那两个颜色在 diff 里已经稳定表示增删，
    /// 在分支图里再用一次，读者会下意识以为它们有关联。
    var lanes: [NSColor] {
        [
            .systemBlue, .systemPurple, .systemTeal, .systemOrange,
            .systemIndigo, .systemPink, .systemBrown, .systemCyan,
        ]
    }
    var laneOnSelection: NSColor { .alternateSelectedControlTextColor }
    var laneNodeCore: NSColor { .textBackgroundColor }
    var laneNodeCoreOnSelection: NSColor { .selectedContentBackgroundColor }

    var laneLineWidth: CGFloat { 1.8 }
    var laneNodeRadius: CGFloat { 4 }

    var diffAddedText: Color { .green }
    var diffDeletedText: Color { .red }
    var diffAddedLine: Color { .green.opacity(0.12) }
    var diffDeletedLine: Color { .red.opacity(0.12) }
    var diffAddedWord: Color { .green.opacity(0.28) }
    var diffDeletedWord: Color { .red.opacity(0.28) }
    var conflict: Color { .orange }
    var danger: Color { .red }

    var syntaxKeyword: Color { .purple }
    var syntaxString: Color { .brown }
    var syntaxComment: Color { .secondary }
    var syntaxNumber: Color { .orange }
    var syntaxType: Color { .teal }
}
