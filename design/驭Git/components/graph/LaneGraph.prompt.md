提交列表里那一行的分支图：轨道、连线、节点。Git 客户端的第一眼印象几乎全来自它。

```jsx
<LaneGraph
  laneCount={6}
  row={{ nodeLane: 1, colorIndex: 1, isHead: true, links: [
    { fromLane: 0, toLane: 0, colorIndex: 0 },
    { fromLane: 1, toLane: 1, colorIndex: 1, isHead: true },
    { fromLane: 2, toLane: 1, colorIndex: 2 },
  ] }}
/>
```

- 图形区宽度 = min(max(24, 轨道数 × 间距), 84)，且永不超过行宽的三分之一。分支图是辅助信息，提交标题才是这个列表存在的理由。
- 选中行传 `emphasized`，并把 `rowBackground` 设成选中背景色：蓝线画在蓝底上等于消失，节点会变成一个白洞。
- 分叉用三次贝塞尔曲线，控制点在行高中点，不要折线。
