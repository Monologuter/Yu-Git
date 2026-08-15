// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MCPKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MCPKit", targets: ["MCPKit"]),
        // Claude Code 以子进程方式拉起 MCP server，所以它必须是一个可执行文件
        .executable(name: "yugit-mcp", targets: ["yugit-mcp"]),
    ],
    dependencies: [
        .package(path: "../GitKit")
    ],
    targets: [
        .target(name: "MCPKit", dependencies: [.product(name: "GitKit", package: "GitKit")]),
        .executableTarget(name: "yugit-mcp", dependencies: ["MCPKit"]),
        .testTarget(name: "MCPKitTests", dependencies: ["MCPKit"]),
    ]
)
