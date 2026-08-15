import AppKit
import SwiftUI

/// 全局视觉规范。
///
/// 只做一件事：把散落在各个视图里的字号、间距、颜色收敛成一处，
/// 让「改一个地方，全局一致」成为可能。
///
/// **一条铁律：颜色一律用系统语义色，不硬编码 RGB。**
/// 语义色不是为了省事，是因为它自动满足三件我们否则要自己维护的事——
/// 深色模式、用户在系统设置里选的强调色、辅助功能里的「增强对比度」。
/// 一旦写死 `Color(red:green:blue:)`，这三样就全都得手工适配，
/// 而且每次 macOS 大版本更新配色时都要返工一遍。
enum Theme {

    // MARK: - 间距
    //
    // 统一走 4 的倍数。不是玄学：macOS 的系统控件（按钮内边距、
    // 列表行内距）本身就按 4pt 网格设计，跟着它排版才能和系统控件对齐。

    enum Spacing {
        /// 2 —— 同一行内紧密相关的两个元素，例如图标和它的文字
        static let hairline: CGFloat = 2
        /// 4 —— 一组内部
        static let tight: CGFloat = 4
        /// 8 —— 默认间距，拿不准时用这个
        static let regular: CGFloat = 8
        /// 12 —— 相关的两组之间
        static let loose: CGFloat = 12
        /// 16 —— 区块之间
        static let section: CGFloat = 16
        /// 24 —— 大块留白
        static let major: CGFloat = 24
    }

    // MARK: - 圆角

    enum Radius {
        /// 4 —— 徽章、小标签
        static let small: CGFloat = 4
        /// 6 —— 按钮、输入框
        static let medium: CGFloat = 6
        /// 10 —— 卡片、面板
        static let large: CGFloat = 10
    }

    // MARK: - 字体
    //
    // 层级只有四档，刻意压得少。字号档位一多，视觉层次反而会糊掉——
    // 读者分辨不出 12 和 13 的差别，只会觉得"乱"。

    enum Font {
        /// 主要内容：提交标题、文件名。用系统默认字号，不放大。
        static var body: SwiftUI.Font { .system(size: 13) }
        /// 次要内容：作者、分支名
        static var secondary: SwiftUI.Font { .system(size: 11) }
        /// 标题：面板标题
        static var title: SwiftUI.Font { .system(size: 15, weight: .semibold) }
        /// 欢迎页的品牌字。
        ///
        /// 和下面的 `mark` 一样只出现在欢迎页与 sheet，**不进主界面**——
        /// 主界面只用 body / secondary / title / mono 四档，多一档层次就糊。
        static var display: SwiftUI.Font { .system(size: 32, weight: .semibold) }
        /// 欢迎页的「驭」字标。
        static var mark: SwiftUI.Font { .system(size: 56, weight: .semibold) }
        /// 说明文本：sheet 正文、空状态的说明句。
        ///
        /// 比 body 小一档、比 secondary 大一档。整段的说明文字用 body 会太重
        /// （它是给单行标题用的），用 secondary 又读着费劲——11pt 适合角标，
        /// 不适合连续阅读的句子。
        static var callout: SwiftUI.Font { .system(size: 12) }
        /// 脚注、免责句。比 secondary 再小一档，只放**读不读都不影响操作**的话。
        ///
        /// 有这一档是为了让 secondary 不被滥用：不给最小档的话，
        /// 所有「不重要的字」都会挤到 11pt，而那一档还担着作者名、计数这些
        /// 需要看清的东西。
        static var caption: SwiftUI.Font { .system(size: 10) }
        /// sheet 标题、命令面板输入框。
        ///
        /// 只用在 sheet 和命令面板，**不进主界面**——主界面的信息密度不允许
        /// 20pt 的字占地方。
        static var sheetTitle: SwiftUI.Font { .system(size: 20, weight: .semibold) }
        /// 等宽：hash、行号、diff 正文
        static var mono: SwiftUI.Font { .system(size: 11, design: .monospaced) }
    }

    /// AppKit 那两处（提交列表、diff 查看器）要用的同一套字体。
    ///
    /// 标 `@MainActor` 是 Swift 6 严格并发的要求：`NSFont` 不是 `Sendable`，
    /// 全局可变状态里放非 Sendable 类型会被编译器拒掉。
    /// 标成主线程隔离既符合事实（AppKit 本来就只能在主线程碰），
    /// 也比 `nonisolated(unsafe)` 那种绕过检查的写法诚实。
    @MainActor
    enum NSFonts {
        static let body = NSFont.systemFont(ofSize: 13)
        static let secondary = NSFont.systemFont(ofSize: 11)
        /// hash 用等宽，**但只给 hash 用**。
        /// 等宽字体渲染中文（人名、提交标题）字距会很难看，
        /// 中文字形本身就是等宽的，再套一层西文等宽只会破坏节奏。
        static let mono = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }

    // MARK: - 颜色
    //
    // 全部转发给当前主题（``ThemeManager/palette``），这里不放任何具体色值。
    //
    // 保持 `Theme.Colors.xxx` 这个静态访问路径是刻意的：界面代码一个字都不用改，
    // 就从「写死系统色」变成了「跟随主题」。换主题时 SwiftUI 会自动重绘，
    // 因为 `@Observable` 的依赖追踪看的是属性访问，不看调用栈有多深。
    //
    // 加新颜色的规矩：先加进 ``ThemePalette`` 协议，再在这里开一个转发。
    // 直接在视图里写死颜色，等于让那一处永远不受主题控制。

    @MainActor
    enum Colors {

        private static var palette: any ThemePalette { ThemeManager.shared.palette }

        // ── 强调色（跟随系统）与品牌色（固定），两者永不互相替代 ──
        static var accent: Color { palette.accent }
        static var onAccent: Color { palette.onAccent }
        static var brand: Color { palette.brand }
        static var brandHover: Color { palette.brandHover }
        static var brandWash: Color { palette.brandWash }
        static var onBrand: Color { palette.onBrand }

        // ── 界面 ──
        static var contentBackground: Color { palette.contentBackground }
        static var sunkenBackground: Color { palette.sunkenBackground }
        static var raisedBackground: Color { palette.raisedBackground }
        static var hoverBackground: Color { palette.hoverBackground }
        static var fillQuaternary: Color { palette.fillQuaternary }
        static var primaryText: Color { palette.primaryText }
        static var secondaryText: Color { palette.secondaryText }
        static var tertiaryText: Color { palette.tertiaryText }
        static var decorativeText: Color { palette.decorativeText }
        static var separator: Color { palette.separator }
        static var separatorStrong: Color { palette.separatorStrong }

        // ── 状态 ──
        static var warning: Color { palette.warning }
        static var warningWash: Color { palette.warningWash }
        static var success: Color { palette.success }
        static var mergeAccent: Color { palette.mergeAccent }

        // ── 分支图 ──
        static var lanes: [NSColor] { palette.lanes }
        static var laneOnSelection: NSColor { palette.laneOnSelection }
        static var laneNodeCore: NSColor { palette.laneNodeCore }
        static var laneNodeCoreOnSelection: NSColor { palette.laneNodeCoreOnSelection }
        static var laneLineWidth: CGFloat { palette.laneLineWidth }
        static var laneNodeRadius: CGFloat { palette.laneNodeRadius }

        /// 旧名，等同于 ``laneOnSelection``。
        ///
        /// 留着是因为它在 AppKit 那两处被反复使用，改名的收益抵不上
        /// 全部改一遍的风险。新代码用 `laneOnSelection`。
        static var onEmphasized: NSColor { palette.laneOnSelection }

        // ── diff ──
        static var diffAddedText: Color { palette.diffAddedText }
        static var diffDeletedText: Color { palette.diffDeletedText }
        static var diffAddedLine: Color { palette.diffAddedLine }
        static var diffDeletedLine: Color { palette.diffDeletedLine }
        static var diffAddedWord: Color { palette.diffAddedWord }
        static var diffDeletedWord: Color { palette.diffDeletedWord }
        static var conflict: Color { palette.conflict }
        static var danger: Color { palette.danger }

        // ── 语法高亮 ──
        static var syntaxKeyword: Color { palette.syntaxKeyword }
        static var syntaxString: Color { palette.syntaxString }
        static var syntaxComment: Color { palette.syntaxComment }
        static var syntaxNumber: Color { palette.syntaxNumber }
        static var syntaxType: Color { palette.syntaxType }
    }
}
