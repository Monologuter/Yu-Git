import AppKit
import Observation
import SwiftUI

/// 当前生效的主题。
///
/// 做成单例而不是走 Environment，是为了让 ``Theme/Colors`` 保持静态访问路径——
/// 界面代码写 `Theme.Colors.accent` 就够了，不必每个视图都注入一次。
/// 代价是它是全局可变状态，所以严格限定在主线程。
///
/// SwiftUI 的刷新照常工作：`@Observable` 的依赖追踪是基于**属性访问**的，
/// 不看调用栈深浅。视图 body 里读 `Theme.Colors.accent`，最终读到
/// `ThemeManager.shared.palette`，这条链会被记为依赖，换主题时视图自动重绘。
///
/// AppKit 那两处（提交列表、diff 查看器）不在这套机制里，
/// 需要显式重绘——见 ``themeDidChange``。
@Observable
@MainActor
final class ThemeManager {

    static let shared = ThemeManager()

    /// 主题变更后发出，AppKit 的视图靠它触发重绘。
    static let themeDidChange = Notification.Name("com.chenya.yugit.themeDidChange")

    /// 所有可选主题。
    ///
    /// 设计稿产出新主题时，实现一个 ``ThemePalette`` 加进这个数组即可，
    /// 界面和持久化都不用改。
    private(set) var available: [any ThemePalette] = [SystemTheme()]

    private(set) var palette: any ThemePalette

    /// 用户选择的主题标识，持久化在 UserDefaults。
    private static let storageKey = "com.chenya.yugit.theme"

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        // 认不出保存的标识就退回默认，而不是崩溃或留空。
        // 这种情况真实存在：用户降级到不含某个主题的旧版本。
        palette = SystemTheme()
        if let saved, let match = available.first(where: { $0.identifier == saved }) {
            palette = match
        }
    }

    func select(_ theme: any ThemePalette) {
        guard theme.identifier != palette.identifier else { return }
        palette = theme
        UserDefaults.standard.set(theme.identifier, forKey: Self.storageKey)
        NotificationCenter.default.post(name: Self.themeDidChange, object: nil)
    }

    /// 注册一套主题。
    ///
    /// 留这个口子是为了让主题定义可以分散在各自的文件里，
    /// 而不是全塞进 `available` 的初始化列表——那样每加一套都要改这个文件。
    func register(_ theme: any ThemePalette) {
        guard !available.contains(where: { $0.identifier == theme.identifier }) else { return }
        available.append(theme)

        // 用户上次选的可能正是这一套，只是当时还没注册上
        if UserDefaults.standard.string(forKey: Self.storageKey) == theme.identifier {
            palette = theme
        }
    }
}
