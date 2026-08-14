分段控件，用于中栏「变更｜历史」这种两三段的切换。

```jsx
<SegmentedControl
  value={section}
  onChange={setSection}
  items={[{ value: 'changes', label: '变更 12' }, { value: 'history', label: '历史' }]}
/>
```

标签里带计数或警示符号（「变更 ⚠」）：有冲突时那不是数量问题，是「先别干别的」的性质问题。计数要去重后的路径数，不能把暂存与未暂存相加。
