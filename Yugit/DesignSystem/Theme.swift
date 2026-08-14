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
    // 全部是语义色。想加新颜色时先问一句：系统有没有现成的语义色表达这个意思？
    // 十有八九是有的。

    enum Colors {
        /// 分支图的轨道配色。
        ///
        /// 刻意避开红绿——那两个颜色在 diff 里已经稳定表示增删，
        /// 在分支图里再用一次，读者会下意识以为它们有关联。
        static let lanes: [NSColor] = [
            .systemBlue, .systemPurple, .systemTeal, .systemOrange,
            .systemIndigo, .systemPink, .systemBrown, .systemCyan,
        ]

        /// 选中且窗口是活跃状态时，画在强调色背景上的前景色。
        ///
        /// 分支图的节点在这种情况下必须换成它。
        /// 否则蓝色节点画在蓝色选中背景上等于消失——
        /// 那正是这一版界面里"选中行的圆点变成一个白洞"的原因。
        static let onEmphasized: NSColor = .alternateSelectedControlTextColor
    }
}
