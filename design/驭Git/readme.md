# 驭Git Design System

macOS 原生 Git 客户端「驭Git」（英文 Yugit）的设计系统。
界面全中文，面向中文开发者；定位是「AI 写代码的时代，帮你驾驭 AI 产出的改动」。
口号：**AI 帮你写代码，驭Git 帮你驾驭它**。

## 来源

这份设计系统由以下材料推导，读者手上可能没有这些东西，但记在这里以便追溯：

- **代码仓库** `https://github.com/Monologuter/Yu-Git`（branch `main`，读的是 `Yugit/` 与 `Packages/GitKit/`）。
  组件清单、尺寸、绘制参数、界面文案都取自这里，不是凭印象写的。详见根目录 `github.md`。
- **视觉设计简报**（用户上传，见 `uploads/design-brief.md`）：现状问题、硬约束、四套主题规划。
- **现有 token** `Yugit/DesignSystem/Theme.swift`（用户上传副本 `uploads/Theme.swift`）。
  结构保留，只改数值。
- **两张现状截图**（用户上传）：历史列表 + 提交详情 + diff 的真实观感。

## 产品与用户

一个人每天连续盯着它 6–8 小时，处理成千上万行代码差异。这条使用强度决定了两件事：
**长时间不能累，信息密度不能低**。所以：

- 同样宽度下能多显示 5 行提交，比留白好看更有价值。
- 分支图是门面，第一眼印象几乎全来自它。
- 所有效果必须能用 SwiftUI + AppKit 标准能力实现：不要复杂渐变、多层阴影、自定义字体、
  需要图片资源的装饰。
- 深浅色模式都要成立，且深浅切换是 macOS 系统级的，与主题正交。

参照：Linear 与 Xcode 的克制专业感；GitKraken 把 commit graph 画得有表现力这一点。
反面：GitKraken 的低信息密度、自绘控件、Electron 观感。

## 这一版做了什么

针对简报里列的四个问题：

1. **零视觉辨识度** → 引入品牌色「靛」`#4A3D8B`（深色 `#938BDA`），出现在系统色管不到的地方：
   当前分支标记、AI 入口、空状态、进度点、品牌字。纯蓝仍然留给系统强调色（选中、焦点），
   因为默认主题要跟随系统。**品牌色不进分支图** —— 那里整块归轨道色，
   多一种颜色就多一次「这是品牌还是某条分支」的判断。
2. **commit graph 太弱** → 线宽 1.8 → 2.5，HEAD 所在轨道 3.5；节点 4.5 环 + 中心挖空；
   合并提交改成实心点、HEAD 加一圈 `--ink-1` 深墨细环（形状区分，不只靠颜色）；
   8 轨道色板重做成等距色相 + 两档明度。
3. **列表缺少节奏** → 新增日期分组行（24pt，粘顶），一行高度换来整列的落点，不动信息密度。
4. **空状态平淡** → `EmptyState` 组件：品牌靛圆底图标 + 标题说清情况 + 一句下一步。

**四套主题 × 浅深，8 组色值全部落地**。默认两组在 `tokens/colors.css`，
墨 / 昼 / 谱 六组在 `tokens/themes.css`。每组一个 `[data-theme]` 单选择器
（`mo` / `mo-dark` / `zhou` / `zhou-dark` / `pu` / `pu-dark`）—— 深浅与主题正交，
应用侧把（主题, 深浅）映射成这一个属性值。三套的取舍写在各自注释里：
墨压色度让非重点后退，昼拉明度差换色盲友好，谱走满饱和。

## 内容规范 CONTENT FUNDAMENTALS

界面语言是中文，由一个每天用中文讨论 Git 的人写，不是机翻。

- **Git 术语保留英文**：`stage`、`rebase`、`hunk`、`upstream`、`commit hash`、`force push`、
  `worktree`、`stash`、`reflog`、`fast-forward`。因为大家实际就是这么说的。
  但**动作用中文**：暂存、取消暂存、丢弃改动、整理提交历史、获取、拉取、推送。
- **不用「您」，也很少用「你」**。多数句子没有主语，直接说事：
  「没有待处理的改动」「upstream 已在远程被删除」。需要主语时用「你」：
  「AI 帮你写代码」「解决并暂存后点「继续」」。自称一律用产品名「驭Git」，不用「我们」。
- **按钮是动词短语，不是「确定」**。危险操作的确认按钮重复动作本身：
  「丢弃这 3 个文件的改动」「删除 kino-aigc-new-fix」「强制删除（含未合并的提交）」。
- **报错必须给下一步**。三段结构：出了什么事 → 为什么 → 现在做什么。
  例：「普通删除会在分支还有未合并提交时被 git 拒绝；强制删除后那些提交只能靠 reflog 找回。」
- **数字照实说**。筛选状态下按钮写「暂存这 12 个」，不写「全部暂存」；
  「在整个历史中找到 37 条」要说清搜的是全量，让人知道结果可信。
- **空状态两句话**：标题写现在是什么情况（「工作区干净」「没有匹配的提交」），
  说明句写下一步或边界（「没有待处理的改动」「整个历史里都没有符合这些条件的提交」）。
- **AI 相关文案有三条铁律**：① 没配服务商时界面上不留任何 AI 痕迹；
  ② 「AI 生成的解释可能有误，请以代码为准」这句一直在，它不是免责声明，是让人保持
  以代码为准的习惯；③ 脱敏做了什么必须说出来（「已排除 .env、私钥等 3 个文件」）。
- **标点**：中文全角，句末不加句号的场合是短标签与角标；括号用中文括号「（）」，
  引用界面元素用直角引号「」。中英之间不加空格（跟随 macOS 中文界面习惯），
  但代码、路径、hash 用等宽字体自然隔开。
- **不用 emoji**。唯一的例外是「变更 ⚠」这个分段标签 —— 那不是装饰，
  是「有冲突，先别干别的」的性质提示，且同时有颜色与字母冗余。
- **语气**：像一个愿意解释原理的资深同事。不卖萌、不惊叹、不用「哦」「啦」；
  也不冷冰冰 —— 该说人话的地方说人话（「记不住在哪就按 ⌘K」「做错了从时间线退回来」）。

## 视觉基础 VISUAL FOUNDATIONS

**颜色**。三条占用规则先于一切：红绿属于 diff；纯蓝属于系统强调色；靛属于品牌。
品牌色靠明度而不是色相跟轨道色区分 —— 去掉绿色系后色相圈上最宽的空隙只有 43°，
任何饱和色相都不可能离 8 条轨道都 ≥25°；轨道活在 L 0.554/0.645，品牌色走 L 0.42。
而分支图里干脆不放品牌色：HEAD 外环用 `--ink-1`。
中性四级承担全部文字层次（`ink-1…4`），11pt 的 hash 与时间用 `ink-3` 而不是系统 tertiary ——
后者在长时间阅读下太淡，也不够 AA。所有色值见 `guidelines/tokens-table.md`。

**排版**。四档，多一档都不加：13 正文 / 11 次要 / 15 semibold 标题 / 11 等宽。
等宽只给 hash、行号、diff 正文、状态字母；中文字形本身等宽，人名与标题套西文等宽会破坏字距。
数字对齐用 `tabular-nums`，不靠换等宽字体。

**间距与网格**。4pt 网格（2 / 4 / 8 / 12 / 16 / 24），因为 macOS 系统控件本身按此设计。
密度优先：提交行 44、分支行 24、diff 行 18。

**背景**。没有图片、没有插画、没有纹理、没有渐变。正文区一律不透明纯色；
唯一的「材质」是侧栏与工具栏的 vibrancy（半透明 + 背景模糊 + 提饱和），
那是 Electron 做不到的质感，也是这个产品「像 Mac 原生应用」的核心卖点之一。
不支持模糊时落到不透明回退色。

**透明与模糊的边界**。只有四处：侧栏、工具栏、diff 的行选择条、sheet 背后的遮罩。
列表、diff 正文、详情面板永不半透明 —— 代码底下有底纹会直接影响可读性。

**圆角**。4 徽章 / 6 按钮与输入框 / 10 卡片与面板 / 胶囊给 ref 徽章与计数。没有第五档。

**卡片长什么样**。这里几乎没有「卡片」：面板之间用 1px hairline 分隔，不用阴影、不用描边框。
需要成块的地方（AI 解释面板、概念说明、等价命令）用 `surface-sunken` 下沉底 + 圆角 6–8，
不加边框也不加阴影。阴影只有两种，都给浮层：popover `0 8px 24px rgba(0,0,0,.16)`、
sheet `0 24px 64px rgba(0,0,0,.24)`。单层，不叠。

**边框**。1px hairline 是主要的分隔手段；输入框与可拖动分隔条用 `hairline-strong`；
聚焦时输入框描 2px 强调色（系统的 `.roundedBorder` 在侧栏背景上太重）。

**hover / press / focus / 选中 / 禁用**。
hover 加一层 `surface-hover` 底色（不改文字颜色、不放大、不加阴影）；
press 再深一档 `surface-press`；focus 描 2px `focus-ring`；
选中行填 `accent-selection`，此时**行内所有前景都要换成能压住它的颜色** ——
文字 100% / 85% / 72% 三档白，分支图与状态字母也一样，否则蓝线画在蓝底上等于消失；
禁用是 40% 不透明度，且必须在 `title` 里说明为什么不能点。
悬停才出现的按钮（分组头、hunk 头、目录行）直接出现，不做淡入 —— 那点延迟只会让人觉得卡。

**动效**。四个时长：90 / 120 / 150 / 220ms，统一 easeInOut。
只做颜色与不透明度过渡，**不做位移、不做弹跳、不做进场序列**。
图标切换（复制→对勾）只淡入淡出，按钮在原地变，视线不用跟着跑。
唯一的循环动画是传输进度的转圈。

**分支图线宽两档，这是信息层级不是装饰**。常规轨道 2.5pt，HEAD 所在轨道 3.5pt。
粗的那条在说「你现在在这里」—— 用线宽表达它，比再塞一个图形标记省地方，
也比只靠颜色可靠：色觉缺陷下线宽照样看得出。HEAD 节点另加一圈品牌色 1.5pt 细环，
形状与颜色双通道。两个值（`--graph-line` / `--graph-line-head`）必须一起改 ——
只改常规的层级就没了，只改 HEAD 的粗细差会大到像故障。

**图像的色彩基调**。没有图像。这不是省事：应用不带任何位图资源，
截图与演示里的「图」只有分支图与 diff 本身。需要视觉重量时靠色板与线宽，不靠图片。

**布局规则**。三栏 NavigationSplitView：侧栏 240（200–340）｜变更/历史 320（260–460）｜详情剩余；
时间线是右侧检查器 300（260–420）。固定元素：52pt 工具栏（红绿灯左起 20pt）、
分组头与 hunk 头 sticky、rebase 横幅横跨三栏挂在顶部（切到哪一栏都看得见）。
分支图最多吃 84pt，且不超过行宽的三分之一。

**保护渐变 vs 胶囊**：不用保护渐变（没有图片需要压字）。需要把文字从背景里拎出来时用胶囊
（ref 徽章、计数）或下沉底块，两者都是实底。

## 图标 ICONOGRAPHY

**应用侧用的是 SF Symbols**，全部由系统提供，仓库里没有一个图标文件、
也没有内置图标字体。用到的大约 60 个符号包括
`arrow.triangle.branch`、`arrow.triangle.merge`、`arrow.triangle.pull`、`cloud`、`tag`、
`line.3.horizontal.decrease`、`sparkles`、`exclamationmark.triangle`、`checkmark.circle`、
`clock.arrow.circlepath`、`camera.fill`、`doc.on.doc`、`ellipsis.circle`、`command` 等。

**这份设计系统不分发图形，只承诺符号名。** SF Symbols 是 SF 字体私有区里的字形，
既不能随设计系统走，网页里也拿不到。拿一套描边 SVG 顶替会同时丢掉四件事 ——
跟随字重、跟随字号、跟随辅助功能的加粗、自动适配深浅 —— 而这四件事正是选它的理由；
顺带还会给一个「不需要任何图片资源」的应用塞进几十个图片。
所以 `Icon` 渲染一个与符号同尺寸的占位框：间距、对齐、基线照真机走，字形留空，
符号名进 `data-sf-symbol` 与 `title`，验收和交接都读它。
**方框不是图标，是图标的位置。** 清单在 `components/core/Icon.prompt.md`。

**要在 Mac 上看到真符号**：页面里塞一张字形表 —— 字形从 SF Symbols.app 的「拷贝符号」拿，
`window.YUGIT_SYMBOL_GLYPHS = { 'arrow.triangle.branch': <这里粘字形>, … }`，
有表的用 SF Pro 直接画，没有的照旧占位。码位不写进文档：编一个私有区码位出来只会画出豆腐块。

**源码里没有对应用法的几个**，需要你定，我没有替你选：`sidebar.left`（左侧栏开关，
源码只有 `sidebar.right`）、`chevron.down` / `chevron.up`、`xmark`（源码只有 `xmark.circle`）、
`person` / `person.circle`（作者现在只用文字）、`arrow.left.and.right`（可拖分隔条）、
`return`（回车提示），以及远程分支 —— 目前复用 `arrow.triangle.branch`。

用法规则：
- 尺寸只用 11（配 11pt 文字）/ 14（配正文与列表行）/ 16（工具栏）三档，外加空状态里的 22。
- 颜色一律 `currentColor`，跟着文字走。三个例外：AI 入口的 `sparkles` 永远品牌靛，
  警示三角永远 `warn`，diff 的 +/− 标记永远 diff 色。
- **状态不许只靠图标或只靠颜色**：文件状态同时有字母（A/M/D/R/C/?/!/·）与颜色；
  合并提交同时有紫色 merge 图标与实心节点。
- 不用 emoji 当图标；不用 Unicode 符号当图标（`⚠` 那一处除外，见内容规范）；
  永远不要手绘 SVG 去凑一个图标。

## 组件 COMPONENTS

27 个，全部来自源码里真实存在的控件。每个目录里有 `<Name>.jsx`、`<Name>.d.ts`、
`<Name>.prompt.md`（怎么用、什么时候用），以及一张 `@dsCard` 演示卡。

- `components/core/` — **Icon**
- `components/controls/` — **Button**、**ToolbarButton**、**SegmentedControl**、**FilterField**、
  **Checkbox**、**CopyButton**
- `components/badges/` — **RefBadge**、**CountPill**、**StatusLetter**、**TrackingBadge**
- `components/graph/` — **LaneGraph**
- `components/rows/` — **CommitRow**、**BranchRow**、**TagRow**、**FileRow**、**DirectoryRow**、
  **SectionHeader**、**DayGroupRow**
- `components/diff/` — **DiffLine**、**HunkHeader**、**SelectionBar**
- `components/feedback/` — **Banner**、**EmptyState**、**ExplanationPanel**、**HazardDialog**、
  **TransferIndicator**

### 有意新增的（源码里没有对应控件）

| 组件 | 为什么加 |
|---|---|
| **Icon** | SF Symbols 无法分发，需要一层替身包装（也是唯一的图标入口） |
| **DayGroupRow** | 简报问题 ③「列表缺少节奏」的答案：日期分组行 |
| **EmptyState** | 把散落在各处的 `ContentUnavailableView` 收成一个，并按简报问题 ④ 重做 |
| **Banner** | 从 `RebaseBanner` 抽出通用形态（warn / danger / info / ok） |
| **SectionHeader**、**CountPill** | 原本内联在 `ChangesView` / `DetailView` 里，抽出来避免各处走样 |

### 没有做的

blame、可视化 rebase、三方合并编辑器、评审面板、并行工作区、PR/MR、AI 设置 ——
这些在源码里都是独立 sheet，尺寸与结构值得单独一轮。要做时请读源码，不要照 UI kit 猜。

## UI kits

- `ui_kits/mac-app/` — 三栏主窗口。可切「变更 / 历史」、点选提交与文件、拖分隔条、
  多选 diff 行、右键丢弃（走危险操作预警）、⌘K 命令面板、时间线检查器、传输进度。
- `ui_kits/first-run/` — 欢迎页 + 六步新手引导（文案取自 `OnboardingStep.repositoryTour`，一字未改）。

两个 kit 都是**复刻**，不是新设计：布局与交互照源码，只把色彩、行高、绘制参数换成新值。

`templates/mac-app/index.html` 与 `templates/first-run/index.html` 是它们的模板入口，
消费项目从这两个文件起稿。模板只是薄薄一层：脚本仍然指向 `ui_kits/` 里的同一份源码，
所以两边永远不会走样。拷进别的项目后，把 head 里那一段注释标出的 `../../`
改成绑定的 `_ds/<folder>` 路径即可。

## 索引

| 路径 | 内容 |
|---|---|
| `styles.css` | 全局入口，只有 @import。消费方 link 这一个文件 |
| `tokens/themes.css` | 墨 / 昼 / 谱 × 浅深 6 组色值 |
| `tokens/colors.css` | 品牌、强调、中性、语义、diff、语法、8 轨道（浅 + 深） |
| `tokens/typography.css` | 字体栈与四档字号（无 @font-face，系统字体） |
| `tokens/spacing.css` | 间距、圆角、描边、阴影、模糊、动效 |
| `tokens/layout.css` | 列宽、行高、sheet 宽度 |
| `tokens/graph.css` | 分支图与 diff 的绘制参数 |
| `guidelines/tokens-table.md` | **全部数值的文本表**：名称 \| 浅色 hex \| 深色 hex \| 用途 |
| `guidelines/*.html` | 19 张基础规范卡（Colors / Type / Spacing / Brand） |
| `components/**` | 27 个组件 + 各自的 d.ts、prompt.md、演示卡 |
| `ui_kits/mac-app/` | 三栏主窗口复刻 |
| `ui_kits/first-run/` | 欢迎页与新手引导 |
| `templates/mac-app/`、`templates/first-run/` | 两个 kit 的模板入口，消费项目可直接照它起稿（复用 `ui_kits/` 里的同一份源码，不重复实现）|
| `github.md` | 仓库关联与同步记录 |
| `SKILL.md` | 供 Claude Code 等 agent 使用的入口说明 |
| `thumbnail.html` | 设计系统首页缩略图 |

## 缺口与替换（需要确认）

1. **字体**：没有字体文件，也不需要 —— 硬约束是「不用自定义字体」，
   界面走 SF Pro + 苹方 + SF Mono，全部系统提供。代价是这里的网页卡片在非 macOS 上
   会落到 system-ui，字距字重与真机有出入。
2. **图标**：只有符号名，没有图形 —— 见上。预览里的虚线方框是位置占位，
   要看真符号需要你提供一张字形表（SF Symbols.app「拷贝符号」）。
   源码里还没有对应用法的 7 个符号已确认可用，列在 `components/core/Icon.prompt.md`。
3. **没有 logo**：仓库里不存在任何图形标志，这份设计系统**没有替它造一个**。
   所有需要「标志」的地方用字组：靛底白「驭」（96×96，圆角 22）或「驭Git」文字。
   如果之后有了真的 logo，替换点只有两处：`ui_kits/first-run/Welcome.jsx` 与 `thumbnail.html`。
4. **8 组色值已全部落地**，但只有默认主题的两组在 UI kit 里看过真实版面 ——
   墨 / 昼 / 谱 六组是按「意图 + 目标对比」解出来的，数值达标（正文 ≥4.5:1、
   diff 叠底可读、轨道相邻 ΔE 记在注释里），但没逐屏走查。
   想让我把 UI kit 加一个主题切换、逐套过一遍，说一声。
5. **深色轨道补上了两档明度规则**。上一版深色有三个明度值（0.699 / 0.750 / 0.800），
   4 与 5 还落在同一档 —— 那是一对相邻 colorIndex，红色弱下 ΔE 只有 2.2，
   等于两条挨着的线糊成一条。归到严格两档（奇 L 0.68 / 偶 L 0.80）后相邻最小 ΔE：
   正常 24.5 / 绿色弱 9.4 / 红色弱 11.1 / 蓝黄弱 13.3，色度一个没降。
   **没有继续往上拉**：要把 28 对全部拉到 10 以上，只能把色度抽到 0.06 一带
   （浅色 1 号会变成 C 0.058 的灰青），那等于放弃简报里最看重的分支图表现力。
   剩下的薄弱对全是非相邻的：深色 2/4 在红色弱下 ΔE 1.5、浅色 6/8 在红色弱下 5.6。
