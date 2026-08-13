# 更新日志

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。版本节奏与 `docs/02-产品需求文档.md` 对齐。

## [未发布]

## [0.1.0] — 2026-08-13 · 内部 Alpha：只读浏览

第一个能跑起来的版本。可以打开仓库，看到分支、标签、工作区变更与提交历史。

### 新增

**Git 引擎（GitKit）**

- **ProcessRunner**：子进程执行器，并发排空 stdout/stderr 防管道死锁，支持超时与取消
- **GitClient**：git CLI 调用层，隔离继承环境、禁止交互挂起、避免 index.lock 竞争
- **StatusParser**：porcelain v2 解析器，覆盖重命名跨段、中文与含空格路径、冲突、submodule
- **LogParser**：提交历史解析，自行解析 ISO 8601 时间戳以满足首屏性能预算
- **RefParser**：分支与 tag 解析，区分附注/轻量 tag，识别 upstream 的 gone 与分叉状态
- **RepoActor**：仓库写操作的单一入口，显式串行化并记录操作日志
- **GitOperation**：操作描述类型，自带中文摘要、注解与等价 git 命令
- **FileOperationLog**：JSONL 操作日志，为 v0.5 的时间线 Undo 打底

**界面**

- 三栏工作区：分支/标签侧栏 ｜ 变更与历史 ｜ 详情
- 欢迎页与最近打开列表
- 支持从 Finder 拖拽或 `open` 命令打开仓库

**工程**

- 工程规范（`docs/04-工程规范.md`）与本地质量门禁（swift-format 配置、git hooks）

### 性能

5 万 commit、400 个工作区文件的基准仓库实测（门槛见 `docs/04-工程规范.md` §8）：

| 操作 | 耗时 | 门槛 |
|---|---|---|
| status | 56ms | < 1s |
| 历史首屏 200 条 | 51ms | < 500ms |
| 分支列表 | 47ms | < 200ms |
| 界面完整刷新 | 63ms | < 1s |

### 已知限制

- 只读。暂存、提交、分支操作在 v0.2
- diff 查看器在 v0.2
- 历史列表用 SwiftUI 实现，大仓库滚动性能待 v0.3 换 AppKit 虚拟化列表
