跟在面板标题后的计数：「改动的文件 2」。

```jsx
<span style={{ font: 'var(--type-title)' }}>改动的文件</span>
<CountPill>2</CountPill>
```

计数一律去重后再数：同一个文件既有已暂存又有未暂存的 hunk 时会出现在两边，直接相加会让数字和眼前的列表对不上。
