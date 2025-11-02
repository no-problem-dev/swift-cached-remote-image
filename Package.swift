// swift-tools-version: 6.0
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
        .package(url: "https://github.com/no-problem-dev/swift-general-domain.git", from: "1.0.0"),
        .package(url: "https://github.com/no-problem-dev/swift-api-client.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "CachedRemoteImage",
            dependencies: [
                "GeneralDomain",
                "APIClient"
            ]
        ),
        .testTarget(
            name: "CachedRemoteImageTests",
            dependencies: ["CachedRemoteImage"],
            path: "Tests"
        )
    ]
)
