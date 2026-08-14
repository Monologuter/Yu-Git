import AppKit
import SwiftUI

extension NSColor {

    /// 从设计稿的十六进制值构造，并自带深色模式的那一份。
    ///
    /// 用 `NSColor(name:dynamicProvider:)` 而不是分别存两个颜色：
    /// 动态颜色由系统在**每次求值时**按当前外观解析，所以深浅切换、
    /// 分屏时两个窗口处于不同外观、以及「增强对比度」这些情况全都自动正确。
    /// 自己判断当前是深是浅再挑一个，这三种情况都会出错——
    /// 尤其第二种，同一个 app 的两个窗口可以处于不同外观。
    ///
    /// - Parameters:
    ///   - light: 浅色模式的值，如 `0x017272`
    ///   - dark: 深色模式的值
    static func theme(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark =
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light, alpha: alpha)
        }
    }

    /// 从 0xRRGGBB 构造。
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {

    /// 见 ``NSColor/theme(light:dark:alpha:)``。
    static func theme(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: .theme(light: light, dark: dark, alpha: alpha))
    }
}
