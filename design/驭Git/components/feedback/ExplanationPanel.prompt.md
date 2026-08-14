AI 中文解释面板，挂在它解释的那个东西旁边（提交说明下面、diff 上面）。

```jsx
<ExplanationPanel title="用中文讲讲这次 commit" text="这次提交把导航栏的弹窗…" />
```

- 没配 AI 服务商时**整块不渲染**，界面上不留任何 AI 痕迹。
- 展开一次请求一次，收起就取消 —— 别烧 token。
- 品牌青的 sparkles 是 AI 入口的统一标志，不要换成系统强调色。
