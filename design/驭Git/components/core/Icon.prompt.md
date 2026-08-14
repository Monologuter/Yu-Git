一个 SF Symbol 的位置；`name` 直接写符号名，和 Swift 侧 `Image(systemName:)` 一字不差。

```jsx
<Icon name="arrow.triangle.branch" size={12} color="var(--brand)" title="当前分支" />
<Icon name="sparkles" size={14} />
<ToolbarButton icon="arrow.down.to.line" title="拉取并合并到当前分支" />
```

- **设计系统只承诺符号名，不分发图形。** SF Symbols 是 SF 字体私有区的字形，不能随设计系统走。
  预览里渲染同尺寸占位框，间距与对齐照真机走，字形留空 —— 不用任何图片资源，
  也不拿描边 SVG 顶替（顶替会丢掉跟随字重、跟随字号、跟随辅助功能加粗、自动适配深浅这四件事）。
- **想在 Mac 上看真符号**：页面里塞字形表，从 SF Symbols.app「拷贝符号」取字形。
  `window.YUGIT_SYMBOL_GLYPHS = { 'arrow.triangle.branch': <这里粘字形> }`，有表的用 SF Pro 画，没有的照旧占位。
  （码位不写在这里 —— 编一个私有区码位出来只会画出豆腐块或者错的符号。）
- 尺寸只四档：11 配 11pt 次要文字，14 配 13pt 正文，16 配工具栏，56 只给空状态。
  要更粗的观感就换字重或换尺寸，不要缩放。
- 语义符号一定给 `title`；纯装饰的留空，组件会 `aria-hidden`。
  不能只靠符号传达状态 —— 状态字母（A/M/D）和文字才是主渠道。

## 清单（全部取自仓库 Swift 源码的真实用法）

| 场景 | 符号 |
|---|---|
| 工具栏 | `chevron.left` 关闭仓库 · `arrow.down.circle` 获取 · `arrow.down.to.line` 拉取 · `arrow.up.to.line` 推送 · `clock.arrow.circlepath` 时间线 · `arrow.clockwise` 刷新 · `ellipsis.circle` 更多 · `command` 命令面板 · `magnifyingglass` 搜索 · `sidebar.right` 详情栏 |
| 侧栏 | `arrow.triangle.branch` 分支 · `tag` 标签 · `plus` 新建 · `line.3.horizontal.decrease` 过滤（激活态 `.circle.fill`）· `xmark.circle.fill` 清空 · `arrow.up`/`arrow.down` ahead/behind · `exclamationmark.triangle` 警示 · `chevron.right` 折叠三角（展开时旋转 90°，源码就是这么做的） |
| 变更与提交 | `checkmark.circle` 干净/完成 · `sparkles` AI 起草与解释 · `checkmark.shield` 自查 · `eye.slash` 未评审部分 · `exclamationmark.triangle(.fill)` 警示与 force push · `trash` 丢弃 · `doc.on.doc` 复制 hash（复制后换 `checkmark`）· `text.alignleft` 改动说明 · `text.bubble` 提交信息 · `pencil` 未提交文件 |
| 文件与 diff | `doc` · `doc.text` · `doc.text.magnifyingglass` 大 diff · `doc.badge.ellipsis` 二进制/不支持 · `equal.circle` 无差异 · `folder` 打开仓库 |
| 历史与操作 | `arrow.triangle.merge` 合并 · `arrow.triangle.pull` rebase · `arrow.uturn.backward` 撤销 · `checklist` 交互式待办 · `square.stack.3d.up(.slash)` 分组提交 · `plus.circle`/`minus.circle` 加入/移出分组 · `arrow.right.circle` 移到某组 · `camera.fill` 时间线快照 · `line.3.horizontal` 拖动把手 |
| 远程与凭据 | `tray.and.arrow.down`/`tray.and.arrow.up` 贮藏与取出 · `tray` Forge 空状态 · `safari` 在浏览器打开 · `key` 令牌 · `lock` 钥匙串与锁定 · `shield` 备份 tag · `square.split.2x1` 并行工作区 |
| 提示 | `info.circle` · `questionmark.circle` · `lightbulb` 顺带一提 · `clock` · `clock.badge.exclamationmark` 超时 · `xmark.circle` 错误 · `circle.lefthalf.filled` 深浅 · `paintpalette` 外观 |

## 设计系统补的 7 个（源码里还没有对应用法，已确认可用）

这几个是标准 SF Symbols，只是当前 Swift 源码还没用到对应位置；写进 UI kit 时按这里的名字来：

| 符号 | 用在哪 |
|---|---|
| `sidebar.left` | 左侧栏开关（源码只有右栏的 `sidebar.right`） |
| `chevron.down` / `chevron.up` | 需要向下/向上箭头的折叠与排序；侧栏折叠三角仍按源码用 `chevron.right` 旋转 |
| `xmark` | 浮层与面板的关闭（源码只有 `xmark.circle`，那是错误态用的） |
| `person` / `person.circle` | 作者头像位；主界面作者仍然只用文字，别默认加头像 |
| `arrow.left.and.right` | 可拖动分隔条的手柄提示 |
| `return` | 回车提示（命令面板、输入框） |
| `cloud` | 远程分支。本地分支用 `arrow.triangle.branch`，远程用它区分，不再共用一个符号 |
