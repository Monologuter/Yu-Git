hunk 头，等宽小字，粘在 diff 滚动区顶部。

```jsx
<HunkHeader header="@@ -161,7 +161,7 @@ public class StoryboardVideoController extends BaseController {"
  action={<Button variant="borderless" size="small">暂存此块</Button>} />
```

hunk 头保留 git 的原文，不要翻译 —— 用户要拿它和终端里的输出对上。
