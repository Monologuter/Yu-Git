// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitKit", targets: ["GitKit"])
    ],
    targets: [
        .target(name: "GitKit"),
        .testTarget(name: "GitKitTests", dependencies: ["GitKit"]),
        // 性能基准。不进日常 swift test，需要一个大仓库才有意义：
        //   python3 scripts/make-benchmark-repo.py 50000 /tmp/yugit-bench
        //   swift run --package-path Packages/GitKit Benchmark /tmp/yugit-bench
        .executableTarget(name: "Benchmark", dependencies: ["GitKit"]),
    ]
)
