<div align="center">

# 驭Git · Yugit

**为「AI 写代码」这件事重做的 macOS 原生 Git 客户端。**

*AI 帮你写代码，驭Git 帮你驾驭它*

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-F05138?logo=swift&logoColor=white)](https://swift.org)
[![UI](https://img.shields.io/badge/UI-SwiftUI%20%2B%20AppKit-blue)](https://developer.apple.com/xcode/swiftui/)
[![Tests](https://img.shields.io/badge/tests-561%20passing-brightgreen)](#测试)
[![Dependencies](https://img.shields.io/badge/dependencies-zero-success)](#为什么零第三方依赖)

[English](./README.md) · [简体中文](./README.zh-CN.md)

</div>

---

## 为什么还要做一个 Git 客户端

因为写代码的方式变了，而 Git 客户端没变。

当 agent 三十秒产出跨九个文件的四百行改动，瓶颈已经不是**写**，而是在它变成一次
提交之前**看懂、验证、拆开**。现有客户端仍然假设每一行都是你自己写的、你记得为什么。

驭Git 是围绕这个变化做的：

- **看懂不是自己写的改动。** 词级行内 diff、语法高亮，以及用中文讲清楚这段 diff、
  这次 commit、这个冲突到底怎么回事。
- **拆开 agent 一次性丢过来的东西。** 按 hunk、按行暂存，把一大坨改动分成几个说得
  清楚的提交，AI 可以先提一个分组方案。
- **什么都能撤。** 每个危险操作前自动打快照。rebase 搞砸了，一键退回去。

还有一件和 AI 无关的事：**整个界面是中文的**——由一个每天用中文讨论 Git 的人写的，
不是机翻的菜单字符串。Git 术语（`stage`、`rebase`、`hunk`）保留英文，因为大家实际
就是这么说的。

## 功能

### 看懂改动

- **词级行内 diff**——一行只改了一个标识符时，只标那个标识符，不是整行刷成红绿
- **语法高亮**，覆盖 12 类语言，逐行分词，所以在 hunk 边界上不会出错
- **AI 中文解释**：任意 diff、commit、合并冲突
- **归因 blame**——逐行看出哪些是人写的、哪些出自 agent
- **全仓库即时搜索**：提交、信息、文件内容、分支

### 攒出一次提交

- **hunk 级与行级暂存**——diff 解析器与 patch 构造器结构同构，往返测试锁死，
  所以部分暂存不会损坏工作区
- **分批提交**——把一大坨改动拆成几次提交，AI 可以给分组建议
- **AI 起草提交信息**，直接落进可编辑的输入框，而不是弹一个「接受/拒绝」
- 提交前的 **AI diff 评审**

### 安全地操作

- **时间线与撤销**——所有写操作走单一入口，危险操作先打快照。
  快照存在 `refs/yugit/*`，不会混进你的历史
- **危险操作预警**一次答完三个问题：会发生什么、能不能撤销、怎么撤销
- **可视化 interactive rebase**——拖动重排、squash、reword
- **三方合并编辑器**
- **透明命令层**——每个操作都显示等价的 `git` 命令加中文注解，
  这个 app 教你 Git，而不是把 Git 藏起来

### 撑得住规模

- **5 万提交的仓库**滚动保持 60fps——提交列表和 diff 视图用 AppKit，其余 SwiftUI
- 基于 `git worktree` 的**并行工作区**
- 上百个文件的变更列表用**文件树**呈现，单子目录链自动合并
- **到处都能筛**——分支、变更文件、提交历史（按信息、作者、时间；
  历史筛选交给 git 跑全量，不是过滤已加载的那一页）

### 平台集成

- **GitHub / GitLab（含自建） / Gitee**——PR、MR 的列表与创建
- **自带 API Key**——Anthropic 与 OpenAI 兼容双协议，Key 存钥匙串，
  不写进配置文件，不参与 iCloud 同步
- 不想自己管 Key 的话，有**可选的订阅服务**

## 安装

> **还没有签名版本。** 签名与公证尚未完成，所以目前从源码构建。
> 这里如实说明，而不是丢一个未签名的二进制让 Gatekeeper 用一句看不懂的话拦住你。

**环境要求：** macOS 14+、Xcode 16+、Git 2.30+

```bash
git clone https://github.com/Monologuter/Yu-Git.git
cd Yu-Git
./scripts/install-hooks.sh          # 执行一次，装上质量门禁
xcodebuild -project Yugit.xcodeproj -scheme Yugit -configuration Release build
```

产物在 Xcode 的 DerivedData 里，从那儿打开；或者直接在 Xcode 里运行。

## 测试

```bash
for pkg in GitKit AIKit ForgeKit; do (cd "Packages/$pkg" && swift test); done
```

58 个 suite、561 条测试。测试刻意偏重**从真实命令输出观察到的 git 边缘 case**，
而不是 mock 出来的行为——CRLF 冲突标记、按路径过滤后配不上对的重命名、
`diff-tree` 对 merge 提交静默返回空、带空格和中文的路径。

规矩是：每踩到一个 git 边缘 case，先补一个 fixture 测试再提交修复。

## 架构

```
Packages/
  GitKit/     进程执行、porcelain 解析、暂存、分支、远程、搜索、时间线快照、
              rebase、冲突、worktree、blame、语法高亮、行内 diff
  AIKit/      Anthropic + OpenAI 兼容双协议、SSE、Keychain、上下文脱敏、
              提交信息、中文解释、解冲突
  ForgeKit/   GitHub / GitLab / Gitee 的 PR/MR
Yugit/        应用层：三栏窗口、命令面板、时间线、设置、可视化 rebase、
              合并编辑器、评审面板、新手引导
server/       云服务网关（Go + PostgreSQL）
```

三条铁律撑着整个设计：

1. **所有仓库写操作走 `RepoActor.perform(_ op: GitOperation)` 单一入口。**
   这是时间线撤销的前提。绕过它直接写是 bug，不是捷径。
2. **每个 `GitOperation` 自带「等价 git 命令 + 中文注解」元数据。**
   透明命令层和命令面板都消费它，所以它们永远不会和真正执行的命令脱节。
3. **`DiffParser` 与 `PatchBuilder` 结构同构，往返测试锁死。**
   这是 hunk 级、行级暂存不损坏工作区的根本保证。

## 技术选型

| 层 | 选择 | 理由 |
|---|---|---|
| 语言 | Swift 6，严格并发 | 数据竞争在编译期就被挡住 |
| 界面 | SwiftUI，提交列表与 diff 视图用 AppKit | SwiftUI 的 `List` 在 5 万行下撑不住 60fps，`NSTableView` 的行复用可以 |
| Git 引擎 | 系统 `git` CLI + porcelain 解析（`-z`、`core.quotepath=false`） | 和用户自己的 git 完全一致——同版本、同配置、同 hooks、同 credential helper |
| AI | Anthropic 原生 + OpenAI 兼容，用户自带 Key | 不锁定厂商；Key 留在钥匙串 |
| 服务端 | Go + PostgreSQL | 常驻 11MB；网关不做推理，只转发和计量 |
| 依赖 | **零第三方** | 见下 |

### 为什么零第三方依赖

Git 客户端的本职是「被信任地对待你的源代码」。每一个依赖都是一处供应链风险，
也是一个下次 macOS 更新可能坏掉的东西。要引入必须书面论证。

影响最大的一次：**放弃 libgit2 / SwiftGit2，改用调用系统 `git`**。
内置的库必然和用户实际拥有的 git 分叉——版本不同、配置解析不同、hooks 不触发、
credential helper 不工作。解析 porcelain 输出更琐碎，但这意味着驭Git 显示的
就是 `git` 会做的。

## 隐私

- **本地 Git 全功能永久免费**，含私有仓库。基础功能没有订阅门槛，以后也不会有。
- **AI 是可选增强。** 不配任何服务商，这个 app 照样完整可用。
- 请求**直连你自己填的服务商**。除非你主动订阅云服务，否则不经过我们任何服务器。
- `.env`、私钥、凭据**永不发送**，每次发送前会告诉你哪些文件被排除了。
- 如果你用云服务，网关**不存任何源代码、不存请求内容**，只记 token 数用于计量。

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/01`](./docs/01-竞品调研与功能设计.md) | 13 款竞品分析；8 个差异化设计的依据 |
| [`docs/02`](./docs/02-产品需求文档.md) | PRD——定位、用户、分版本需求、AI 设计铁律、商业模式 |
| [`docs/03`](./docs/03-实现计划.md) | 架构、里程碑、风险清单、验收标准 |
| [`docs/04`](./docs/04-工程规范.md) | 工程规范——分支、提交、代码、测试、安全、发布 |
| [`CONTRIBUTING.md`](./CONTRIBUTING.md) | 如何参与 |
| [`server/README.md`](./server/README.md) | 云服务网关部署 |

## 进度

`docs/03` 里的全部里程碑均已实现——v0.1 到 v2.0，加上列为「远期」的部分。
当前版本 **v2.2.0**。

剩下的是发布工程：签名与公证、超大仓库的性能实测、用真实 key 的端到端验证。

## 致谢

`docs/01` 的竞品调研研究了 Fork、Tower、GitKraken、Sourcetree、SmartGit、
GitButler、Lazygit、Sublime Merge、GitHub Desktop、Gitless、Magit、Git Cola、GitUp。
这里的若干设计是对它们做对了什么——以及做错了什么——的直接回应。

本 README 的结构参考 [cc-haha](https://github.com/NanmiCoder/cc-haha)。
