# swift-cached-remote-image

SwiftUI でリモート画像をキャッシュ付きで表示するパッケージ

## 概要

`swift-cached-remote-image` は、SwiftUI でリモート画像を効率的に読み込み、メモリとディスクキャッシュで管理するためのパッケージです。非同期画像読み込み、リトライポリシー、カスタマイズ可能なプレースホルダーなどの機能を提供します。

## 必要要件

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## インストール

### Swift Package Manager

`Package.swift` に以下を追加してください：

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-cached-remote-image.git", from: "1.0.0")
]
```

または Xcode で：
1. File > Add Package Dependencies
2. パッケージ URL を入力: `https://github.com/no-problem-dev/swift-cached-remote-image.git`
3. バージョンを選択: `1.0.0` 以降

## 使い方

### 基本的な使用例

```swift
import SwiftUI
import CachedRemoteImage

struct ContentView: View {
    var body: some View {
        CachedRemoteImage(
            url: URL(string: "https://example.com/image.jpg")!
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            ProgressView()
        }
    }
}
```

### ImageService を使った高度な使用例

```swift
import CachedRemoteImage

// ImageService を環境変数として注入
@main
struct MyApp: App {
    @State private var imageService = ImageServiceImpl()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.imageService, imageService)
        }
    }
}

// ビュー内で使用
struct ProfileView: View {
    @Environment(\.imageService) var imageService
    let imageEntity: ImageEntity

    var body: some View {
        CachedRemoteImage(
            entity: imageEntity,
            configuration: .init(
                cachePolicy: .default,
                retryPolicy: .exponential(maxAttempts: 3)
            )
        )
    }
}
```

## 機能

- ✅ SwiftUI ネイティブな API
- ✅ メモリ & ディスクキャッシュ
- ✅ 非同期画像読み込み（async/await）
- ✅ カスタマイズ可能なリトライポリシー
- ✅ プレースホルダーとエラー表示のカスタマイズ
- ✅ ImageService による環境値注入
- ✅ Firebaseストレージ対応

## 依存関係

- [swift-general-domain](https://github.com/no-problem-dev/swift-general-domain) - ドメインモデル
- [swift-api-client](https://github.com/no-problem-dev/swift-api-client) - HTTP クライアント

## ライセンス

MIT License

Copyright (c) 2024 NOPROBLEM

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
