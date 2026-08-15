# MCPKit · 驭Git 的 MCP Server

把驭Git 的能力暴露给 Claude Code 之类的 agent。

## 为什么做这个

此前是驭Git 调 AI。MCP 让方向反过来：**Claude Code 调驭Git**。
GUI 因此成为 agent 的操作台，而不是 agent 的替代品——
slogan「AI 帮你写代码，驭Git 帮你驾驭它」到这里才真正兑现。

## 配置

编译出可执行文件：

```bash
cd Packages/MCPKit && swift build -c release
```

写进 Claude Code 的 MCP 配置：

```json
{
  "mcpServers": {
    "yugit": {
      "command": "/绝对路径/yugit-mcp",
      "args": ["/绝对路径/你的仓库"]
    }
  }
}
```

不传 `args` 时用当前工作目录。Claude Code 拉起子进程时的 cwd 通常就是项目根，
所以多数情况下不用配。

## 给出的四个工具

挑选标准是**只给 agent 做不到、或做起来很容易做错的事**。
agent 已经能直接跑 `git status`、`git log`——把那些包一层没有任何价值，
还会让工具列表变长、让模型选错。

| 工具 | 干什么 | 为什么值得单独给 |
|---|---|---|
| `yugit_snapshot` | 给整个工作区拍快照 | Claude Code 的 checkpoint 只管它自己写过的文件。用户同时在编辑器里改的、终端里跑 git 造成的改动，它都不管——而那恰恰是出事时最难恢复的部分 |
| `yugit_timeline` | 列出能退回的时间点 | 出事之后有据可查 |
| `yugit_restore` | 退回某个时间点 | 整个工作区（含未跟踪文件）一起退。退回这个动作本身也会先拍一张，因此可再退回来 |
| `yugit_explain` | 问一条 git 操作危不危险 | 「会发生什么、能不能撤、怎么撤」三答，来自 app 内同一套危险预警 |

## 两条设计上的硬约束

**`yugit_explain` 走白名单，不接受自由拼装的 git 命令。**
这个 server 有能力写用户的仓库，让模型自由拼命令行等于把一把没有保险的枪交出去。
白名单意味着最坏情况也只是执行了表里某一条我们已经理解并加了预警的操作。

**`yugit_restore` 按 id 精确匹配，不做模糊查找。**
这一步会覆盖工作区，猜错一条的代价是用户几个小时的活。

## 分层

| 文件 | 管什么 |
|---|---|
| `JSONRPC.swift` | JSON-RPC 2.0 的编解码。纯函数 |
| `MCPServer.swift` | MCP 协议：握手、列工具、调工具。不碰 IO |
| `YugitTools.swift` | 四个工具的实现，靠 `GitKit` 干活 |
| `StdioTransport.swift` | 唯一碰 IO 的一层，按行读写 stdout |

协议与 IO 分开，是因为最容易错的几处全在协议层，而它们全部可以用纯函数测出来：
通知不能回响应、id 是数字就得回数字、工具自己失败不是协议错误、
响应必须压成一行。这些在 `Tests/` 里都有对应的测试。
