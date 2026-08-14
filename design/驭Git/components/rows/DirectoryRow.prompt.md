文件树里的目录行。

```jsx
<DirectoryRow name="ai-web/frontend/src" count={12} collapsed={false}
  action={<Button variant="borderless" size="small">暂存</Button>} />
```

默认全展开：打开变更列表就是为了看有哪些文件，默认折叠等于每次都要先点开一遍。目录行不是可选中的对象，别让它抢走文件的选中态。
