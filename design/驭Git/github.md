repo: Monologuter/Yu-Git
branch: main
path: Yugit

## Last sync

date: 2026-08-14T16:22:00Z

### Updated in this project

- 从 Yugit/DesignSystem/Theme.swift 与各 Feature 视图提取间距、圆角、字号、绘制参数
- 重做色彩系统：品牌青、8 轨道分支图色板、diff 与语法色板（默认主题浅/深两组）
- 按 Swift 源码还原组件库与 macOS 三栏 UI kit、首次运行引导

## Screen map

| 项目文件 | 仓库来源 |
|---|---|
| tokens/*.css | Yugit/DesignSystem/Theme.swift |
| ui_kits/mac-app/index.html | Yugit/Features/Repository/RepositoryView.swift |
| ui_kits/mac-app/Sidebar.jsx | Yugit/Features/Sidebar/SidebarView.swift |
| ui_kits/mac-app/ChangesPane.jsx | Yugit/Features/Changes/ChangesView.swift, Changes/FileRow.swift |
| ui_kits/mac-app/HistoryPane.jsx | Yugit/Features/History/CommitGraphView.swift, History/CommitRow.swift |
| ui_kits/mac-app/DetailPane.jsx | Yugit/Features/Detail/DetailView.swift, Diff/DiffView.swift |
| ui_kits/mac-app/Toolbar.jsx | Yugit/Features/Repository/RepositoryView.swift |
| ui_kits/mac-app/CommandPalette.jsx | Yugit/Features/CommandPalette/CommandPalette.swift, CommandRegistry.swift |
| ui_kits/first-run/index.html | Yugit/Features/Repository/RootView.swift, Teaching/OnboardingView.swift |
| ui_kits/first-run/Tour.jsx | Packages/GitKit/Sources/GitKit/Teaching/HazardWarning.swift（OnboardingStep.repositoryTour）|
| ui_kits/mac-app/Timeline.jsx | Yugit/Features/Timeline/TimelineView.swift |
| templates/mac-app, templates/first-run | 上述两个 kit 的模板入口 |
| components/** | 同名 Swift 视图（见各 .prompt.md 首行）|
