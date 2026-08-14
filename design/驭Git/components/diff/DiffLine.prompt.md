diff 的一行：双列行号、+/- 标记、代码内容。

```jsx
<DiffLine kind="deletion" oldNumber={164} segments={[
  { text: '@Operation(summary = ', syn: 'plain' },
  { text: '"S2 ', syn: 'string' },
  { text: '多模态', syn: 'string', changed: true },
  { text: '生成视频"', syn: 'string' },
  { text: ')' },
]} />
```

- 上下文行不参与选择：它在两边都存在，谈不上暂存与否。
- 行号绝不参与压缩 —— 被挤掉一位数字的行号是错的行号，比不显示更糟。
- 语法色只有五类（关键字、字符串、注释、数字、类型），一律避开红绿。
