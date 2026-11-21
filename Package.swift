// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LyricBubbles",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "LyricBubbles", path: "Sources/LyricBubbles"),
        .testTarget(name: "LyricBubblesTests", dependencies: ["LyricBubbles"], path: "Tests/LyricBubblesTests"),
    ]
)
