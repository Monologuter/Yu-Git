单个图标，包了一层 mask 让 SVG 跟随 currentColor；应用侧的 SF Symbols 在这里由 Lucide 同义图标替身。

```jsx
<Icon name="git-branch" size={14} />
<Icon name="triangle-alert" size={11} color="var(--warn)" title="有冲突" />
```

- 图标目录默认解析为 `../../assets/icons/`（组件卡与 UI kit 都在两级深度）。别的深度在页面里设 `window.YUGIT_ICON_BASE`。
- **这是替换品，不是原物。** 应用跑的是 SF Symbols，无法随设计系统分发。Lucide 是最近的一档：同为描边、圆头端点、2px 标称线宽。做视觉验收时以 macOS 上的真机截图为准。
- 常用映射：`arrow.triangle.branch`→git-branch，`arrow.triangle.merge`→git-merge，`arrow.triangle.pull`→git-pull-request，`cloud`→cloud，`tag`→tag，`line.3.horizontal.decrease`→list-filter，`sparkles`→sparkles，`exclamationmark.triangle`→triangle-alert，`checkmark.circle`→circle-check，`clock.arrow.circlepath`→rotate-ccw，`doc.on.doc`→copy，`ellipsis.circle`→ellipsis，`sidebar.right`→panel-right，`square.split.2x1`→columns-2，`square.stack.3d.up`→layers，`eye.slash`→eye-off，`arrow.uturn.backward`→undo-2。
- 线宽在 mask 里改不了。要更粗的观感就换更大的 size，不要缩放。
