// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CachedRemoteImage",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // ビューと protocol。APIClient に依存しないので、
        // Infrastructure を知らない Presentation 層がこれだけを取れる
        .library(
            name: "CachedRemoteImage",
            targets: ["CachedRemoteImage"]),
        // APIClient を使う既定の ImageTransport 実装
        .library(
            name: "CachedRemoteImageAPIClient",
            targets: ["CachedRemoteImageAPIClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "3.0.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", .upToNextMajor(from: "1.4.0"))
    ],
    targets: [
        .target(
            name: "CachedRemoteImage"
        ),
        .target(
            name: "CachedRemoteImageAPIClient",
            dependencies: [
                "CachedRemoteImage",
                .product(name: "APIClient", package: "swift-api-client")
            ]
        ),
        .testTarget(
            name: "CachedRemoteImageTests",
            dependencies: ["CachedRemoteImage"]
        ),
        .testTarget(
            name: "CachedRemoteImageAPIClientTests",
            dependencies: [
                "CachedRemoteImageAPIClient",
                .product(name: "APIClient", package: "swift-api-client")
            ]
        )
    ]
)
