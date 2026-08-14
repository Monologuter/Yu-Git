跨栏状态横幅：状态还在就一直挂着，把出路做成按钮。

```jsx
<Banner
  headline="整理提交时遇到冲突"
  detail="进行到第 2 / 5 条。冲突文件：ConflictView.swift。解决并暂存后点「继续」。"
  footnote="放弃后仍可用备份 tag yugit/backup-1712 回到整理之前的状态"
  actions={<><Button>放弃整理</Button><Button variant="default" disabled title="还有冲突没解决">继续</Button></>}
/>
```

「放弃」放左、「继续」放右：继续是需要先解决冲突的那条路，不该做成一眼就想点的默认选项。
