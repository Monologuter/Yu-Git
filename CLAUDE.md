# 驭Git（Yugit）

AI 原生 + 中文界面的 macOS 原生 Git 客户端。Slogan：「AI 帮你写代码，驭Git 帮你驾驭它」。Bundle ID `com.chenya.yugit`。

## 现状（2026-08-14）

**v2.2 已发布。`docs/03-实现计划.md` 里的全部内容——v0.1 → v2.0 六个里程碑
加上远期方向——均已实现。** 561 条测试全绿。

云服务已上线：`https://yugit.educy.top`（Let's Encrypt，自动续期已验证），
上游走通义，服务端源码在 `server/`。

- `Packages/GitKit` — 进程、status/log/diff 解析、暂存（含 hunk/行级）、分支、远程、
  搜索、时间线快照、interactive rebase、Quick Actions、分批提交、冲突解析、
  worktree、blame 与 AI 归因、危险操作预警
- `Packages/AIKit` — Anthropic 原生 + OpenAI 兼容双协议、SSE、Keychain、上下文脱敏、
  提交信息生成、中文解释、Commit Composer、解冲突建议、diff 评审、
  对话式操作计划、云服务客户端
- `Packages/ForgeKit` — GitHub / GitLab（含自建）/ Gitee 的 PR/MR 列表与创建
- `Yugit` — 三栏窗口、⌘K 命令面板、时间线侧栏、AI 设置页、可视化 rebase、
  拆分提交、三方合并编辑器、评审面板、并行工作区、归因 blame、平台面板、
  对话式操作、新手引导

**唯一未完成的部分是云服务的服务端**（客户端已就绪，界面上标注为「尚未开放」）。
后续工作属于打磨与发布：签名公证、真实 key 的端到端验证、大仓库性能实测。

远程：私有仓库 `https://github.com/Monologuter/Yu-Git`，默认分支 `main`。

## 必读文档

- `docs/01-竞品调研与功能设计.md` — 13 款竞品的精华/糟粕分析、8 个差异化设计的依据
- `docs/02-产品需求文档.md` — PRD：定位、目标用户、分版本功能需求、AI 设计铁律、非功能指标、商业模式
- `docs/03-实现计划.md` — 架构、里程碑（v0.1→v0.3→v0.5→v1.0→v2.0）、风险清单、验收标准
- `docs/04-工程规范.md` — 分支/tag/提交/代码/测试/安全/发布规范与质量门禁
- `docs/05-迭代清单.md` — **持续迭代的依据**。开工前先读它，动了任何一项回来更新状态。
  里面还列明了哪些事必须停下来问用户（审美判断、优先级变更、不可逆操作、对外发布）

## 工程纪律（细则见 04 文档）

- 提交信息：Conventional Commits + **英文**摘要（祈使语气，≤72 字符）；正文也用英文。
  代码注释与文档保持中文——提交历史会流传到 GitHub 列表、blame、bisect 输出里，
  读者范围比界面广得多。**绝不加任何 AI 协作署名**（commit-msg hook 会拦截）
- 分支：轻量流。文档与小修直接提 main；新模块、多 commit 的功能、危险重构走 `feat/*` 分支，rebase 后 `--ff-only` 合入
- 提交前跑 `swift format --recursive --in-place Packages/ Yugit/`；推送前 `swift test` 必须全绿
- 新克隆后执行一次 `./scripts/install-hooks.sh` 装上门禁
- 默认零第三方依赖，引入需书面论证

## 架构铁律（早埋，晚补要返工）

- 所有仓库写操作走 `RepoActor.perform(_ op: GitOperation)` 单一入口——时间线 Undo 的前提，绕过入口直接写视为 bug
- 每个 `GitOperation` 自带「等价 git 命令 + 中文注解」元数据——透明命令层和 Command Palette 直接消费
- DiffParser 与 PatchBuilder 同构，往返测试锁死——hunk/行级暂存不损坏工作区的根本保证

## 关键决策（已与用户确认，勿擅自推翻）

- Swift + SwiftUI/AppKit 原生，目标 macOS 14+；提交历史列表和 diff 视图这两处用 AppKit 保性能，其余 SwiftUI
- Git 引擎：调用系统 git CLI + porcelain 解析（`-z` + `core.quotepath=false`），**不用 libgit2/SwiftGit2**
- AI：用户自带 API Key（OpenAI 兼容 + Anthropic 双协议），Key 存 Keychain；所有 AI 动作可预览、可编辑、可撤销
- 商业模式：本地 Git 全功能永久免费（含私有仓库），绝不对基础功能收订阅
- 分发：Developer ID 签名 + 公证，不开沙盒，暂不上 App Store

## 协作约定

- 全程用中文沟通；Git 术语保留英文
- 用户是资深全栈开发者，但正在边学 Swift 边做——涉及 Swift/SwiftUI 特有概念时适当多解释一句
- 工程质量：每修一个 git 边缘 case 补一个 fixture 测试；性能指标见 PRD 第 5 节
