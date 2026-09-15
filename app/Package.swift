// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PostMD",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.0")
    ],
    targets: [
        // Pure logic library. Tests @testable import only this target.
        // Importing the executable target (top-level code in main.swift) directly tends to break swift test.
        .target(
            name: "PostMDCore",
            path: "Sources/PostMDCore"
        ),
        .executableTarget(
            name: "PostMD",
            dependencies: [
                "PostMDCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui")
            ],
            path: "Sources/PostMD"
        ),
        .testTarget(
            name: "PostMDTests",
            dependencies: ["PostMDCore"],
            path: "Tests/PostMDTests"
        )
    ]
)
