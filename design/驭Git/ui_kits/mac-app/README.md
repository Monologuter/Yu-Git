# UI kit · macOS 三栏工作区

驭Git 主窗口的高保真复刻。按 `Yugit/Features/` 下的 SwiftUI / AppKit 源码逐处对照，
不是新设计 —— 色彩、行高、绘制参数换成了本设计系统的新值，布局与交互照原样。

## 文件

| 文件 | 对应源码 |
|---|---|
| `index.html` | `Repository/RepositoryView.swift`（三栏 + 工具栏 + sheet 组装） |
| `Toolbar.jsx` | 同上的 `.toolbar { … }` 部分 |
| `Sidebar.jsx` | `Sidebar/SidebarView.swift` |
| `ChangesPane.jsx` | `Changes/ChangesView.swift` + `Changes/FileRow.swift` |
| `HistoryPane.jsx` | `History/CommitGraphView.swift` + `History/CommitRow.swift` |
| `DetailPane.jsx` | `Detail/DetailView.swift` + `Diff/DiffView.swift` |
| `CommandPalette.jsx` | `CommandPalette/CommandPalette.swift`（560×380，输入框 20pt，右侧等价 git 命令） |
| `Timeline.jsx` | `Timeline/TimelineView.swift`（检查器 300pt） |
| `data.js` | 演示数据，取自用户提供的截图（仓库 ai-cloud） |

## 能点什么

- 分段控件切「变更 / 历史」；历史列表点选提交 → 右栏出提交详情，再点文件 → 下半部分出 diff（分隔条可拖）
- 变更列表点文件 → 右栏出该文件 diff；diff 里点行可多选，出现行级暂存条
- 右键变更列表 → 上下文菜单 → 「丢弃改动…」→ 危险操作预警
- ⌘K 或工具栏「更多」→ 命令面板（↑↓ 选择，Esc 关闭）
- 工具栏时间线按钮 → 右侧时间线检查器，点任一条展开等价 git 命令
- 获取 / 拉取 / 推送 → 传输进度，期间三个按钮禁用
- 侧栏折叠、远程分支与标签折叠、过滤框、AI 起草（900ms 后把文案填进提交框）

## 有意省略

blame（`Blame/BlameView.swift`）、可视化 rebase（`Rebase/RebaseView.swift`）、
三方合并编辑器（`Conflict/ConflictView.swift`）、评审（`Review/ReviewView.swift`）、
并行工作区（`Worktree/WorktreeView.swift`）、PR/MR（`Forge/ForgeView.swift`）、
AI 设置（`Settings/AISettingsView.swift`）都是独立 sheet，这一版没有复刻。
它们要做的时候请以源码为准，不要照这个 kit 猜。
