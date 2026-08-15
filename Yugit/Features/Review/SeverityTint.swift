import AIKit
import SwiftUI

extension ReviewFinding.Severity {

    /// 这一档意见用什么颜色。
    ///
    /// 走主题层而不是 `.red` / `.orange`：换主题时系统色不跟着变，
    /// 一片重新配过色的界面里剩几点原色，看起来像渲染出了 bug。
    @MainActor var tint: Color {
        switch self {
        case .critical: Theme.Colors.danger
        case .warning: Theme.Colors.warning
        case .info: Theme.Colors.accent
        case .nitpick: Theme.Colors.secondaryText
        }
    }
}
