// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SetupRushTrader",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SetupRushTrader", path: "Sources/SetupRushTrader")
    ]
)
