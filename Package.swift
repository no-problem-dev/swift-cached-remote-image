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
        .library(
            name: "CachedRemoteImage",
            targets: ["CachedRemoteImage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "2.3.1"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", .upToNextMajor(from: "1.4.0"))
    ],
    targets: [
        .target(
            name: "CachedRemoteImage",
            dependencies: [
                .product(name: "APIClient", package: "swift-api-client")
            ]
        ),
        .testTarget(
            name: "CachedRemoteImageTests",
            dependencies: [
                "CachedRemoteImage",
                .product(name: "APIClient", package: "swift-api-client")
            ],
            path: "Tests"
        )
    ]
)
