// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MarkdownKit",
    platforms: [
        .iOS(.v17),
        .macOS("26.0") // Targeting macOS 26.0 per user request
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MarkdownKit",
            targets: ["MarkdownKit"]
        ),
        .executable(
            name: "MarkdownKitDemo",
            targets: ["MarkdownKitDemo"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0"),
        .package(url: "https://github.com/colinc86/MathJaxSwift.git", from: "3.4.0"),
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", from: "1.17.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MarkdownKit",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Splash", package: "Splash"),
                .product(name: "MathJaxSwift", package: "MathJaxSwift")
            ]
        ),
        .executableTarget(
            name: "MarkdownKitDemo",
            dependencies: ["MarkdownKit"]
        ),
        .testTarget(
            name: "MarkdownKitTests",
            dependencies: [
                "MarkdownKit",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
