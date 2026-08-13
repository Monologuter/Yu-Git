// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ForgeKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ForgeKit", targets: ["ForgeKit"])
    ],
    targets: [
        .target(name: "ForgeKit"),
        .testTarget(name: "ForgeKitTests", dependencies: ["ForgeKit"]),
    ]
)
