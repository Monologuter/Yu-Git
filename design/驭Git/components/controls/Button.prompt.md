按钮：默认动作、普通推按钮、行内文字按钮、破坏性动作四种外观，尺寸跟随系统控件高度。

```jsx
<Button variant="default" onClick={commit}>提交</Button>
<Button icon="sparkles" title="根据暂存的改动起草提交信息">AI 起草</Button>
<Button variant="borderless" size="small">全部暂存</Button>
<Button variant="destructive">丢弃改动…</Button>
```

- 一屏里只允许一个 `variant="default"`，它代表回车会触发的那个动作。
- `borderless` 用于列表分组头、行内出现的动作（悬停才显形的那些）。文案照实说数量：「暂存这 12 个」而不是「全部暂存」。
- 禁用不解释就是不合格：给 `title` 说明为什么不能点（例：「先暂存一些改动，AI 才知道要描述什么」）。
