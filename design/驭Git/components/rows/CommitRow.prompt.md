历史列表里的一行提交。这是这个应用被看得最多的一行，别在它上面加东西。

```jsx
<CommitRow
  subject="fix: 导航新增弹窗" hash="6b054b88" author="李泽林" date="4 个月前"
  laneCount={6} graphRow={{ nodeLane: 1, colorIndex: 1, links: [] }}
  refs={[{ kind: 'local', name: 'kino-aigc-chenya' }]}
/>
```

- 44px 两行：标题一行，hash·作者·时间一行。时间右对齐，hash 与时间永不被压缩，作者名先截断。
- 合并提交在标题前加一个紫色 merge 图标，节点同时换成实心点 —— 两处冗余是故意的。
- 选中时所有文字换成压得住强调色背景的前景色（85% / 72% 两档），分支图同理。
