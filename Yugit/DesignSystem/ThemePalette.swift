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

    // MARK: - 强调色与品牌色
    //
    // 这是两个角色，**永不互相替代**：
    //
    // - `accent` 跟随用户在系统设置里选的强调色。选中行、默认按钮、焦点环用它，
    //   因为那是 macOS 的既定习惯——用户把系统调成粉色，选中行就该是粉色。
    // - `brand` 是产品自己的颜色，固定不变。当前分支标记、AI 入口、空状态、
    //   品牌字用它，那些地方系统色管不到，也正是产品辨识度的来源。
    //
    // 把两者合成一个的话，要么选中态失去系统一致性，要么品牌完全消失——
    // 现在这一版界面「看不出是驭Git」，根因就是只有 accent 没有 brand。

    /// 系统强调色。
    var accent: Color { get }
    /// 画在强调色背景上的前景色。
    ///
    /// 单独给一个而不是固定用白色：低对比主题的强调色可能很浅，白字压不住。
    var onAccent: Color { get }

    /// 品牌色。
    var brand: Color { get }
    /// 品牌色元素的悬停与按下态。
    var brandHover: Color { get }
    /// 品牌色的极浅底，用于空状态圆底、信息横幅。
    var brandWash: Color { get }
    /// 画在品牌色上的前景。
    var onBrand: Color { get }

    // MARK: - 界面

    /// 窗口正文底。
    var contentBackground: Color { get }
    /// 下沉面：hunk 头、说明面板、分组头。
    var sunkenBackground: Color { get }
    /// 浮起面：sheet、popover、命令面板。
    var raisedBackground: Color { get }
    /// 行与按钮的悬停底。
    var hoverBackground: Color { get }

    var primaryText: Color { get }
    var secondaryText: Color { get }
    var tertiaryText: Color { get }
    /// 装饰与禁用。**永不承载文字信息**——它的对比度不足以阅读。
    var decorativeText: Color { get }

    var separator: Color { get }
    /// 更实一档的描边：输入框、可拖动分隔条。
    var separatorStrong: Color { get }

    // MARK: - 状态

    var warning: Color { get }
    var success: Color { get }
    /// 合并提交、改名/复制状态字母。
    var mergeAccent: Color { get }

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

    // 强调色一律走系统的，不落死值——用户在系统设置里改了，界面要跟着改
    var accent: Color { .accentColor }
    var onAccent: Color { Color(nsColor: .alternateSelectedControlTextColor) }

    var brand: Color { .theme(light: 0x01_7272, dark: 0x5C_C6B9) }
    var brandHover: Color { .theme(light: 0x00_5F5F, dark: 0x7B_D6CB) }
    var brandWash: Color { .theme(light: 0xDC_F9F8, dark: 0x0A_3535) }
    var onBrand: Color { .theme(light: 0xFF_FFFF, dark: 0x08_211F) }

    var contentBackground: Color { .theme(light: 0xFF_FFFF, dark: 0x18_1A1C) }
    var sunkenBackground: Color { .theme(light: 0xF7_F8F9, dark: 0x0F_1113) }
    var raisedBackground: Color { .theme(light: 0xFD_FDFE, dark: 0x23_2528) }
    var hoverBackground: Color { .theme(light: 0xEE_F0F3, dark: 0x2C_2E31) }

    // ink 三级比系统的 tertiaryLabelColor 深一档：hash 和时间是要读的信息，
    // 系统那一档在浅色下只有 3.3:1，够不上 AA
    var primaryText: Color { .theme(light: 0x15_1618, dark: 0xEE_F0F3) }
    var secondaryText: Color { .theme(light: 0x55_585C, dark: 0xA2_A5A9) }
    var tertiaryText: Color { .theme(light: 0x6F_7276, dark: 0x83_868B) }
    var decorativeText: Color { .theme(light: 0x9C_9FA2, dark: 0x5B_5E62) }

    var separator: Color { .theme(light: 0xDD_E0E3, dark: 0x32_3437) }
    var separatorStrong: Color { .theme(light: 0xCB_CED2, dark: 0x4B_4D51) }

    var warning: Color { .theme(light: 0x9F_6200, dark: 0xF1_AF57) }
    var success: Color { .theme(light: 0x05_773B, dark: 0x65_C281) }
    var mergeAccent: Color { .theme(light: 0x7F_4BB1, dark: 0xC6_99F8) }

    /// 等距色相 + 两档明度（OKLCH L 0.555 / 0.645）。
    ///
    /// 两档明度而非全等明度是刻意的：8 个等明度色相在色觉缺陷下必然有几对
    /// 糊在一起，而明度是那时唯一还可靠的通道。两档只差 0.09，
    /// 正常视力看不出「脏」。相邻 colorIndex 永远跨明度档。
    ///
    /// 全部避开红绿——那两个色相被 diff 独占。
    var lanes: [NSColor] {
        [
            .theme(light: 0x00_857A, dark: 0x0C_B6A8),  // 1 青 185°
            .theme(light: 0xA6_65E5, dark: 0xD1_A9FF),  // 2 紫 305°
            .theme(light: 0x9A_6704, dark: 0xFC_AB05),  // 3 琥 75°
            .theme(light: 0x08_9DC1, dark: 0x0B_AFD7),  // 4 蓝 222°
            .theme(light: 0xB6_3795, dark: 0xF6_7BD1),  // 5 玫 340°
            .theme(light: 0x00_A86E, dark: 0x0D_CD88),  // 6 碧 160°
            .theme(light: 0x3A_68E0, dark: 0x6E_9AFF),  // 7 靛 265°
            .theme(light: 0xE8_5A0E, dark: 0xFE_8959),  // 8 赭 42°
        ]
    }
    var laneOnSelection: NSColor { .white }
    var laneNodeCore: NSColor { .theme(light: 0xFF_FFFF, dark: 0x18_1A1C) }
    var laneNodeCoreOnSelection: NSColor { .selectedContentBackgroundColor }

    // 3pt 而不是 1.8pt。这是「看起来专不专业」影响最大的单个数值：
    // 细线在 Retina 上被渲染成一根发丝，整张图显得单薄廉价；
    // 加粗之后曲线才有分量，分叉合并的走向也才看得清。
    // 这也是 GitKraken 唯一值得照搬的地方。
    var laneLineWidth: CGFloat { 2.5 }
    var laneNodeRadius: CGFloat { 4.5 }

    // 不用 opacity 叠出来，而是各给一个实色。
    // 半透明色叠在不同底色上会得到不同结果——选中行、悬停行、
    // 分组头下方的底色都不一样，用 opacity 的话每种组合都要重新验对比度。
    var diffAddedText: Color { .theme(light: 0x05_773B, dark: 0x6A_D18A) }
    var diffDeletedText: Color { .theme(light: 0xAD_3232, dark: 0xFF_847D) }
    var diffAddedLine: Color { .theme(light: 0xE3_FBE8, dark: 0x1B_3422) }
    var diffDeletedLine: Color { .theme(light: 0xFF_EEEC, dark: 0x44_2321) }
    var diffAddedWord: Color { .theme(light: 0xB3_EDC1, dark: 0x1C_5430) }
    var diffDeletedWord: Color { .theme(light: 0xFE_D0CB, dark: 0x70_312E) }
    var conflict: Color { .theme(light: 0x9F_6200, dark: 0xF1_AF57) }
    var danger: Color { .theme(light: 0xB6_3132, dark: 0xF9_7770) }

    var syntaxKeyword: Color { .theme(light: 0x6D_389E, dark: 0xC7_97FD) }
    var syntaxString: Color { .theme(light: 0x8E_421B, dark: 0xEE_A471) }
    var syntaxComment: Color { .theme(light: 0x7B_8187, dark: 0x81_878D) }
    var syntaxNumber: Color { .theme(light: 0x89_5603, dark: 0xEB_B25F) }
    var syntaxType: Color { .theme(light: 0x06_6565, dark: 0x6B_CAC9) }
}
