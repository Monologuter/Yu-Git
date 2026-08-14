# UI kit · 首次运行

| 文件 | 对应源码 |
|---|---|
| `Welcome.jsx` | `Yugit/Features/Repository/RootView.swift` 的 `WelcomeView` |
| `Tour.jsx` | `Yugit/Features/Teaching/OnboardingView.swift`，文案取自 `Packages/GitKit/Sources/GitKit/Teaching/HazardWarning.swift` 的 `OnboardingStep.repositoryTour` |

## 与源码的两处差异

1. **品牌标志**。源码用 SF Symbol `arrow.triangle.branch`（56pt, light, tint）。
   仓库里没有任何图形 logo，这份设计系统也不替它造一个 —— 改为 96×96 青底白「驭」，
   全部由文字和圆角矩形构成，SwiftUI 两行就能写出来。
2. **进度点** 用品牌青而不是系统强调色：它是品牌出现的地方之一，且不与选中态争色。

引导六步的文案一字未改。顺序按真实工作流排（看改动 → 挑改动 → 提交 → 历史 → 时间线 → ⌘K），
不按 Git 的概念体系排；概念解释挂在用到它的那一步旁边，不做术语表。
