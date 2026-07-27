// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// このパッケージは**依存を持たない**。
//
// 4.0 で「取り方はアプリ、キャッシュはパッケージ」に責務を入れ替えた時、取り方の既定実装
// （APIClient を使う URLImageTransport）を別ターゲットに分けれ ば利用者が APIClient を
// 巻き込まずに済む、と考えたが**それは効かない**。SPM の依存解決はパッケージ単位なので、
// 使わないターゲットのために宣言した依存も利用者の解決空間に入る。実際、api-client 1.x 世代の
// アプリが 4.0.0 を取り込もうとして解決不能になった（swift-authentication 1.x → api-client 1.x
// と、このパッケージの api-client 3.x が両立しない）。
//
// 分けるならパッケージごと分けるしかない。そして URLImageTransport は ImageTransport の
// 3 メソッドを HTTP で埋めるだけのもので、アプリが既に持っている HTTP スタックで書けば 30 行に
// 満たない。使われない実装を同梱して、利用者の依存グラフに制約を持ち込む釣り合いではない。
//
// → 取り方の実装は利用者が持つ。このパッケージが持つのは protocol・キャッシュ・ビューだけ。
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
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", .upToNextMajor(from: "1.4.0"))
    ],
    targets: [
        .target(
            name: "CachedRemoteImage"
        ),
        .testTarget(
            name: "CachedRemoteImageTests",
            dependencies: ["CachedRemoteImage"]
        )
    ]
)
