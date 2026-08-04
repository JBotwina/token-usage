// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenUsage",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TokenUsage",
            path: "Sources/TokenUsage"
        )
    ]
)
