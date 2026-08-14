复制按钮，紧跟在它复制的那个值后面。

```jsx
<span style={{ font: 'var(--type-mono)' }}>4115987c</span>
<CopyButton text="4115987c9d0e…" title="复制完整 commit hash" />
```

界面上只显示短 hash：完整 hash 的用途是粘到别处，不是阅读；40 个字符在窄面板里必然折行，折了连双击选中都做不到。
