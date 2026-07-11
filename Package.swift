// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftUIChatMarkdown",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "SwiftUIChatMarkdown", targets: ["SwiftUIChatMarkdown"])
    ],
    dependencies: [
        .package(url: "https://github.com/mgriebling/SwiftMath", exact: "1.7.3"),
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.8.0"),
        .package(url: "https://github.com/lukilabs/beautiful-mermaid-swift", exact: "1.0.4")
    ],
    targets: [
        .target(
            name: "SwiftUIChatMarkdown",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "SwiftMath", package: "SwiftMath"),
                .product(name: "BeautifulMermaid", package: "beautiful-mermaid-swift")
            ],
            path: "Sources/SwiftUIChatMarkdown"
        ),
        .testTarget(
            name: "SwiftUIChatMarkdownTests",
            dependencies: ["SwiftUIChatMarkdown"],
            path: "Tests/SwiftUIChatMarkdownTests"
        )
    ]
)
