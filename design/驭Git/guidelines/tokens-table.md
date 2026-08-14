# 数值表

图片没法取色，这里是所有色值与尺寸的文本形式。格式：`名称 | 浅色 hex | 深色 hex | 用途`。
**只有「默认」主题落了值**（浅 / 深两组）。墨 / 昼 / 谱 三套等风格确认后再补，届时结构不变、只换数值。

## 品牌

| 名称 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| brand | #4A3D8B | #938BDA | 品牌靛。当前分支标记、AI 入口、空状态图标、进度点、品牌字。**不进分支图** |
| brand-hover | #3C2E7A | #A8A7E3 | 品牌色元素的悬停 / 按下 |
| brand-wash | #F2F2FF | #282841 | 空状态圆底、信息横幅底 |
| brand-wash-strong | #E6E5FF | #38375B | 需要更实一档的品牌浅底 |
| brand-on | #FFFFFF | #12101F | 画在品牌色上的前景 |

## 系统强调色（默认主题跟随系统，此处为系统默认蓝）

| 名称 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| accent | #007AFF | #0A84FF | controlAccentColor：默认按钮、焦点环、命令面板图标 |
| accent-selection | #0064E1 | #145EC1 | 选中行背景 |
| accent-on | #FFFFFF | #FFFFFF | alternateSelectedControlTextColor |
| accent-wash | #E8F1FF | #12233A | 选中行的浅底（diff 选中行 22% 混色） |

## 中性

| 名称 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| ink-1 | #151618 | #EEF0F3 | 正文：提交标题、文件名、分支名（浅色 18.1:1） |
| ink-2 | #55585C | #A2A5A9 | 次要：作者、分支计数、说明句（7.2:1） |
| ink-3 | #6F7276 | #83868B | 三级：hash、时间、行号（4.8:1，比系统 tertiary 深，够 AA） |
| ink-4 | #9C9FA2 | #5B5E62 | 装饰与禁用，永不承载文字信息 |
| surface-app | #FFFFFF | #181A1C | 窗口正文底（textBackgroundColor） |
| surface-sunken | #F7F8F9 | #0F1113 | hunk 头、说明面板、分组头（underPageBackgroundColor） |
| surface-raised | #FDFDFE | #232528 | sheet、popover、命令面板 |
| surface-sidebar | rgba(243,245,247,.72) | rgba(33,35,38,.68) | 侧栏 / 工具栏 vibrancy，配 blur(30) saturate(180%) |
| surface-sidebar-opaque | #F3F5F7 | #212326 | 不支持模糊时的回退 |
| surface-hover | #EEF0F3 | #2C2E31 | 行与按钮的悬停 |
| surface-press | #E4E6EA | #383B3E | 按下 |
| fill-quaternary | #E9EBEE | #2E3033 | 计数胶囊、过滤框底 |
| hairline | #DDE0E3 | #323437 | 分栏线、行分隔、分组头下缘 |
| hairline-strong | #CBCED2 | #4B4D51 | 输入框描边、可拖动分隔条 |

## 语义

| 名称 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| warn | #9F6200 | #F1AF57 | 冲突、rebase 半途、force push、轻量提醒（5.0:1） |
| warn-wash | #FFEDD8 | #3A2A0E | 警示横幅底 |
| danger | #B63132 | #F97770 | 不可逆操作的按钮与文字（6.0:1） |
| danger-wash | #FEEBE9 | #3D1F1D | 危险区域底 |
| ok | #05773B | #65C281 | 干净、可合、已复制（5.7:1） |
| ok-wash | #DBF9E2 | #15301F | 完成态底 |
| merge | #7F4BB1 | #C699F8 | 合并提交图标、改名/复制状态字母（5.9:1） |

## diff（红与绿在此独占）

| 名称 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| diff-add-row | #E3FBE8 | #1B3422 | 新增行整行底；正文在其上 15.9:1 |
| diff-add-word | #B3EDC1 | #1C5430 | 新增行里真正变了的那几段，叠在整行底之上；正文 13.1:1 |
| diff-add-fg | #05773B | #6AD18A | + 标记、+N 统计 |
| diff-del-row | #FFEEEC | #442321 | 删除行整行底 |
| diff-del-word | #FED0CB | #70312E | 删除行词级底 |
| diff-del-fg | #AD3232 | #FF847D | − 标记、−N 统计 |

## 语法高亮（5 类，避开红绿）

| 名称 | 浅色 | 深色 | 用途 |
|---|---|---|---|
| syn-keyword | #6D389E | #C797FD | 关键字（7.8:1） |
| syn-string | #8E421B | #EEA471 | 字符串（7.1:1） |
| syn-comment | #7B8187 | #81878D | 注释（3.9:1，唯一允许低于 4.5 的一类） |
| syn-number | #895603 | #EBB25F | 数字（6.2:1） |
| syn-type | #066565 | #6BCAC9 | 类型名（6.9:1） |
| syn-plain | = ink-1 | = ink-1 | 其余代码 |

## 分支图 8 轨道

等距色相 + 两档明度（OKLCH L 0.555 / 0.645，色度取各色相在 sRGB 内的上限）。
相邻 colorIndex 永远跨明度档。

| 名称 | 浅色 | 深色 | 色相 / 用途 |
|---|---|---|---|
| lane-1 | #00857A | #00B0A2 | 靛青 185°，主线默认落这一轨 |
| lane-2 | #A665E5 | #D1A9FF | 紫 305° |
| lane-3 | #9A6704 | #CB8900 | 琥 75° |
| lane-4 | #089DC1 | #47D0F9 | 蓝 222° |
| lane-5 | #B63795 | #DE65BA | 玫 340° |
| lane-6 | #9C9023 | #D1C12A | 柘 103° |
| lane-7 | #3A68E0 | #6894F8 | 靛 265° |
| lane-8 | #E85A0E | #FFA37E | 赭 42° |
| lane-on-emphasized | #FFFFFF | #FFFFFF | 选中行上的线与节点一律换成它 |

色觉校验（Viénot 模拟）：浅色组红色弱下最近的一对距离 23、绿色弱 16（紫 vs 靛，
两者在色板顺序里隔五位）；深色组两种模拟下最近 31。全部 ≥ 3:1 对背景。

## 字号（pt）

| 名称 | 值 | 用途 |
|---|---|---|
| body | 13 regular | 提交标题、文件名、分支名 |
| secondary | 11 regular | 作者、计数、角标、行内说明 |
| title | 15 semibold | 面板标题 |
| mono | 11 regular | hash、行号、diff 正文、状态字母 |
| callout | 12 regular | sheet 与说明文本（SwiftUI .callout） |
| caption | 10 regular | 脚注、免责句（.caption2） |
| sheet-title | 20 semibold | sheet 标题、命令面板输入框（.title3） |
| display | 32 semibold | 欢迎页品牌字 |
| mark | 56 semibold | 欢迎页「驭」字标 |

字重只用 400 / 500 / 600。字体：SF Pro Text（西文）+ 苹方（中文）+ SF Mono（等宽），
全部系统提供，不打包字体文件。

## 间距 · 圆角 · 描边（pt）

| 名称 | 值 | 用途 |
|---|---|---|
| space-hairline | 2 | 同一行内紧密相关的两个元素 |
| space-tight | 4 | 一组内部 |
| space-regular | 8 | 默认 |
| space-loose | 12 | 相关的两组之间 |
| space-section | 16 | 区块之间 |
| space-major | 24 | 大块留白（仅 sheet 与欢迎页） |
| radius-small | 4 | 徽章、状态底、选中的文件行 |
| radius-medium | 6 | 按钮、输入框、分段控件 |
| radius-large | 10 | 卡片、面板、sheet |
| border-width | 1 | hairline |
| border-focus-width | 2 | 聚焦环 |

## 布局（pt）

| 名称 | 值 | 用途 |
|---|---|---|
| col-sidebar | 240（200–340） | 左栏 |
| col-changes | 320（260–460） | 中栏 |
| col-inspector | 300（260–420） | 时间线检查器 |
| toolbar-height | 52 | 工具栏 |
| row-commit | 44 | 提交行（两行文字） |
| row-day-group | 24 | 日期分组行（本版新增） |
| row-list | 24 | 分支 / tag 行 |
| row-file | 30（带目录副行 38） | 变更文件行 |
| row-diff | 18 | diff 单行 |
| sheet-width-sm | 460 | 危险操作预警、失败详情 |
| sheet-width-md | 520 | 新手引导 |
| palette | 560 × 380 | 命令面板 |
| indent-tree | 12 | 文件树每级缩进 |

## 分支图绘制参数（pt）

| 名称 | 现值 | 原值 | 说明 |
|---|---|---|---|
| graph-lane-gap | 14 | 14 | 轨道水平间距 |
| graph-lane-gap-min | 5 | 5 | 压缩下限 |
| graph-width-min | 24 | 24 | 图形区最窄 |
| graph-width-max | 84 | 84 | 图形区最宽，且不超过行宽 34% |
| graph-line | **2.5** | 1.8 | 曲线线宽 |
| graph-line-head | **3.5** | — | HEAD 所在轨道加粗一档 |
| graph-node-r | **4.5** | 4 | 普通提交：环 |
| graph-node-hole | 2.6 | 1.6 内缩 | 中心挖空半径 |
| graph-node-merge-r | **3.2** | — | 合并提交：实心点 |
| graph-head-ring-r | **6.5** | — | HEAD 外圈细环半径 |
| graph-head-ring-w | **1.5** | — | HEAD 外圈线宽（`--ink-1` 深墨，不用品牌色） |
| diff-gutter-digit | 7 | 7 | 行号列按最大行号位数 × 7 + 10 |
| diff-marker-width | 14 | 14 | +/− 标记列 |
| diff-selected-bar | 3 | 3 | 选中行左侧竖条 |

## 动效

| 名称 | 值 | 用途 |
|---|---|---|
| dur-instant | 90ms | 即时反馈 |
| dur-fast | 120ms | 焦点环、hover |
| dur-medium | 150ms | 图标淡入淡出 |
| dur-slow | 220ms | sheet 出现 |
| ease-standard | cubic-bezier(.42, 0, .58, 1) | 全部动画共用（等价 easeInOut） |
| blur-sidebar | blur(30) saturate(180%) | 侧栏 vibrancy |
| blur-toolbar | blur(20) saturate(180%) | 工具栏 |
| blur-overlay | blur(12) saturate(140%) | 选择条、sheet 背后 |

## 主题 · 墨 / 昼 / 谱（各浅深两组，共 6 组）

默认主题的两组在上面。这 6 组住 `tokens/themes.css`，每组一个单选择器：
`[data-theme="mo"|"mo-dark"|"zhou"|"zhou-dark"|"pu"|"pu-dark"]`。深浅与主题正交，
应用侧把（主题, 深浅）映射成这一个属性值。下表只列承重的 18 个；
完整 50 个 token 与每组实测对比见 `tokens/themes.css` 的注释。

| 名称 | 墨浅 | 墨深 | 昼浅 | 昼深 | 谱浅 | 谱深 | 用途 |
|---|---|---|---|---|---|---|---|
| brand | #514A88 | #857FC3 | #423384 | #8E86D8 | #4B3A96 | #887ED7 | 品牌靛 |
| ink-1 | #3C3730 | #CBC3BB | #0F1112 | #E5E7EA | #1C2027 | #DCE3EF | 正文 |
| ink-2 | #68625A | #979189 | #4E5153 | #A3A6A8 | #535861 | #9CA2AD | 次要 |
| ink-3 | #766F68 | #89827A | #5C5E61 | #929497 | #696D77 | #848A95 | 三级 hash/时间 |
| surface-app | #FAF6EF | #1E1914 | #FFFFFF | #090B0C | #FBFCFF | #13161D | 窗口底 |
| surface-sunken | #F2EEE7 | #14100B | #F1F3F5 | #030405 | #F1F2F6 | #0A0D13 | 下沉块 |
| surface-sidebar-opaque | #F0EBE3 | #231E17 | #E9EBED | #101214 | #EAECF1 | #191C25 | 侧栏回退色 |
| hairline | #DBD6CF | #39332D | #B6B8BA | #3D3F41 | #D0D2D5 | #33373F | 分隔线 |
| hairline-strong | #C0BBB4 | #534D47 | #858688 | #636567 | #ADAFB2 | #525760 | 描边 |
| warn | #95601E | #B17C3D | #9F630C | #AD7021 | #9E6100 | #B77419 | 警示 |
| danger | #B74744 | #D6635D | #C54542 | #D3524E | #C93B3B | #E25350 | 危险 |
| ok | #2A7A47 | #479560 | #1E8246 | #2F8E52 | #018040 | #2A9554 | 完成 |
| merge | #8258AF | #9E73CC | #8B59BE | #9867CC | #8C54C1 | #A16AD9 | 合并 |
| diff-add-row | #DFFAE5 | #152D1C | #D1FFDC | #001D09 | #D5FEDE | #042B13 | 新增整行底 |
| diff-del-row | #FFEDEB | #3A1E1C | #FFEDEB | #300505 | #FFEDEB | #3C1513 | 删除整行底 |
| syn-keyword | #73479F | #A579D4 | #7E45B3 | #A169D9 | #813CBD | #AD6AEE | 关键字 |
| syn-string | #8B4C27 | #BF7D57 | #994C17 | #BF6E3E | #9C4700 | #CE7036 | 字符串 |
| syn-type | #00675F | #429B90 | #006D64 | #029388 | #006C63 | #009B8E | 类型名 |

### 8 轨道在各主题下

| 轨道 | 墨浅 | 墨深 | 昼浅 | 昼深 | 谱浅 | 谱深 |
|---|---|---|---|---|---|---|
| lane-1 靛青 | #308279 | #42ACA0 | #007268 | #009B8F | #008277 | #00B0A2 |
| lane-2 紫 | #AA66EC | #CCABF4 | #B25AFF | #D5B1FF | #B35EFF | #D5B1FF |
| lane-3 琥 | #936A2A | #C28D3A | #845800 | #B37900 | #976500 | #CB8900 |
| lane-4 蓝 | #3B9BB8 | #52CDF3 | #009FC3 | #4ED6FF | #00A0C5 | #4ED6FF |
| lane-5 玫 | #B83396 | #F049C5 | #A90087 | #E400B7 | #C0009A | #FF15CE |
| lane-6 柘 | #9A9036 | #CCBF4A | #9F9200 | #D9C700 | #A19300 | #D9C700 |
| lane-7 靛 | #3666E7 | #6E95EE | #1139FF | #487BFF | #2558FF | #6492FF |
| lane-8 赭 | #DB6635 | #F5A688 | #EC5900 | #FFAD8D | #EE5A00 | #FFAD8D |

三套主题对轨道的取舍不同：墨为了让非重点后退，色度压到 ×0.82（相邻 colorIndex 最小 ΔE 6.9，
六组里最松）；昼把两档明度差从 0.09 拉到 0.155，相邻最小 ΔE 13.0，且最细的线也过 3:1，
色盲友好是它的设计目标；谱走满饱和。
