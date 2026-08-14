侧栏里的一行分支。

```jsx
<BranchRow name="kino-aigc-chenya" isCurrent title={'kino-aigc-chenya\nupstream：origin/kino-aigc-chenya'} />
<BranchRow name="origin/kino-aigc-new-fix" isRemote behind={1} />
```

- 当前分支永远置顶：光按最后提交时间排，切到一个很久没动的分支后它会沉到几十个分支的末尾 —— 而那恰恰是你此刻站着的地方。
- 远程分支常有几十个，默认折叠，展开状态要记住。
- tooltip 里补 upstream、分叉情况、最新提交，行内放不下的信息都在那儿。
