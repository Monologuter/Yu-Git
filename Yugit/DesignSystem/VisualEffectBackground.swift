import AppKit
import SwiftUI

/// 把 `NSVisualEffectView` 当背景用。
///
/// 这是 Electron 做不到的那种质感，也是「像 Mac 原生应用」最便宜的一票：
/// 侧栏半透明地透出桌面壁纸，跟着窗口是否活跃变浓淡。
///
/// **用系统材质而不是自己调「半透明底色 + 高斯模糊」。** 设计稿写的是
/// `blur(30) saturate(180%)` 配一层 72% 的浅底，那是 CSS 里描述这个效果的方式；
/// 在 macOS 上照着实现是走弯路——系统材质自带三件我们否则要手工维护的事：
/// 深浅模式各一份、窗口失焦时自动变淡、以及辅助功能里的「降低透明度」。
/// 最后那条尤其重要：勾上它之后系统会把材质换成不透明底色，
/// 而自己画的模糊不会理会这个设置。
struct VisualEffectBackground: NSViewRepresentable {

    var material: NSVisualEffectView.Material = .sidebar
    /// 默认取窗口背后的内容（桌面、其他窗口）。
    /// `.withinWindow` 取的是同一窗口里压在下面的视图，那是给浮层用的。
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        // 跟着窗口的活跃状态走。写死 .active 的话，切到别的 app 之后
        // 侧栏仍然浓墨重彩，和系统其余部分对不上，反而显得这个窗口没失焦。
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
