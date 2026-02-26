// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MyMarkdown",
    platforms: [
        .iOS(.v17),
        .macOS("26.0") // Targeting macOS 26.0 per user request
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MyMarkdown",
            targets: ["MyMarkdown"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", branch: "main"),
        .package(url: "https://github.com/JohnSundell/Splash.git", from: "0.16.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MyMarkdown",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Splash", package: "Splash")
            ]
        ),
        .testTarget(
            name: "MyMarkdownTests",
            dependencies: ["MyMarkdown"]
        ),
    ]
)
