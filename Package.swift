// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "YouTubeInsight",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "YouTubeInsight", targets: ["YouTubeInsight"])
    ],
    targets: [
        .executableTarget(
            name: "YouTubeInsight",
            path: "Sources/YouTubeInsight"
        ),
        .testTarget(
            name: "YouTubeInsightTests",
            dependencies: ["YouTubeInsight"],
            path: "Tests/YouTubeInsightTests"
        )
    ]
)
