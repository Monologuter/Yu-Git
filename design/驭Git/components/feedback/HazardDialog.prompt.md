不可逆操作前的预警对话框。

```jsx
<HazardDialog
  title="确定丢弃这 3 个文件的改动？"
  whatHappens="这 3 个文件会回到 HEAD 的内容，未提交的改动全部消失。"
  undoable="可以。操作前会自动打一个快照。"
  howToUndo="在时间线里找到「丢弃改动」这一条，点撤销。"
  command="git restore --worktree -- a.swift b.swift c.swift"
  confirmLabel="丢弃这 3 个文件的改动"
/>
```

确认按钮文案必须重复动作本身，不能只写「确定」—— 用户点的时候要能再确认一次自己在做什么。
