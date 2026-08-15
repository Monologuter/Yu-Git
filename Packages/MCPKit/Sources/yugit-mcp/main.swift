import Foundation
import GitKit
import MCPKit

// 驭Git 的 MCP server。由 Claude Code 以子进程方式拉起，走 stdio。
//
// 配置方式（写进 Claude Code 的 MCP 配置）：
//     "yugit": { "command": "/path/to/yugit-mcp", "args": ["/path/to/repo"] }
//
// 不传路径时用当前工作目录——Claude Code 拉起子进程时的 cwd 通常就是项目根，
// 所以多数情况下不用配 args。

/// 日志一律走 stderr。
///
/// **stdout 是协议信道**，往里写一行别的东西，客户端那边就是一条解析失败的消息，
/// 而且表现为「server 莫名其妙不响应了」——排查起来极其费劲。
func log(_ message: String) {
    FileHandle.standardError.write(Data(("yugit-mcp: " + message + "\n").utf8))
}

let arguments = CommandLine.arguments.dropFirst()
let path = arguments.first ?? FileManager.default.currentDirectoryPath

do {
    let client = try GitClient()
    let repository = try await RepoActor.open(
        at: URL(fileURLWithPath: path, isDirectory: true), client: client)

    let server = MCPServer(name: "yugit", version: "1.0.0")
    for tool in YugitTools.all(for: repository) {
        await server.register(tool)
    }

    log("已在 \(repository.root.path) 上就绪")
    await StdioTransport(server: server).run()
} catch {
    // 启动失败也要说清是哪个路径出的问题：多数情况是 args 指错了目录，
    // 而 Claude Code 那边只会显示「server 启动失败」
    log("无法在 \(path) 上启动：\(error)")
    exit(1)
}
