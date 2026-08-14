复选框，用于「修改上一条提交」这类开关。

```jsx
<Checkbox checked={isAmending} onChange={setAmending} label="修改上一条提交" />
```

勾选会改变后果时，紧跟一行 11pt 的后果说明（例：「修改后 commit hash 会变，若已推送则需要 force push」），用 `--warn`。
