空状态。四栏里出现的每一处空白都该是它，而不是一片纯白。

```jsx
<EmptyState icon="circle-check" title="工作区干净" description="没有待处理的改动" />
<EmptyState icon="file-search" tone="warn" title="这个 diff 很大"
  description="共 12480 行变化，展开可能需要一点时间"
  action={<Button>仍然展开</Button>} />
```

标题写「现在是什么情况」，说明句写「下一步做什么」。「没有匹配的提交」后面要跟「整个历史里都没有符合这些条件的提交」—— 让人知道搜的是全量，结果是可信的。
