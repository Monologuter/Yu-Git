# 更新日志

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。版本节奏与 `docs/02-产品需求文档.md` 对齐。

## [未发布]

## [0.2.0] — 2026-08-13 · 内部 Alpha：提交工作流

从只读浏览进到能干活。可以看 diff、逐 hunk 或逐行暂存、提交与 amend，
外部改动实时反映到界面。

### 新增

**diff 与暂存**

- **DiffParser / PatchBuilder**：解析与生成构成同构关系，用往返测试锁死。
  这是 hunk / 行级暂存不损坏用户文件的根本保证
- 整文件、hunk、行三个粒度的暂存与取消暂存
- 丢弃改动、stash push / pop
- diff 查看器：行号、增删标记、逐 hunk 暂存按钮，超 2000 行先折叠

**实时性**

- **RepositoryWatcher**：基于 FSEvents，300ms 防抖，写操作期间可挂起。
  终端里的 git、编辑器保存、agent 写的代码都能立刻反映到界面

**提交**

- 提交面板，amend 时自动带出上一条说明并提示 hash 会变

### 修复的隐患

- **CRLF 文件的 diff 被整块吞掉**：Swift 把 `\r\n` 当作单个 Character，
  `String.split(separator: "\n")` 完全不分割。改为按字节切分，
  行尾的 `\r` 也因此原样保留，暂存不会把换行符从 CRLF 改成 LF
- **无尾换行的文件被补上换行**：`\ No newline at end of file` 标记
  必须随 patch 原样带上
- **历史首屏慢 7 倍**：`--date-order` 带拓扑约束，要遍历完整提交图。
  改用 git 原生排序，界面刷新 396ms → 63ms

### 性能

5 万 commit、400 个工作区文件的基准仓库实测：

| 操作 | 耗时 | 门槛 |
|---|---|---|
| 界面完整刷新 | 62ms | < 1s |
| 历史首屏 200 条 | 48ms | < 500ms |
| 单文件 diff | 44ms | < 200ms |
| 增删行数统计 | 49ms | < 500ms |

### 已知限制

- 分支切换、fetch/pull/push 在 v0.3
- 历史列表用 SwiftUI 实现，大仓库滚动性能待 v0.3 换 AppKit 虚拟化列表
- 冲突只能标记，解决冲突的界面在 v1.0

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
