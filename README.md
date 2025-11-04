# swift-cached-remote-image

SwiftUI でリモート画像をキャッシュ付きで表示するパッケージ

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

📚 **[完全なドキュメント](https://no-problem-dev.github.io/swift-cached-remote-image/documentation/cachedremoteimage/)**

## 概要

`swift-cached-remote-image` は、SwiftUI でリモート画像を効率的に読み込み、メモリとディスクキャッシュで管理するためのパッケージです。非同期画像読み込み、リトライポリシー、カスタマイズ可能なプレースホルダーなどの機能を提供します。

### 主な機能

- ✅ **SwiftUI ネイティブな API** - SwiftUI と完全に統合された使いやすいインターフェース
- ✅ **メモリ & ディスクキャッシュ** - 自動的な二層キャッシュで高速表示
- ✅ **非同期画像読み込み** - async/await を使った現代的な並行処理
- ✅ **柔軟な ImageSource** - URL、URL 文字列、画像 ID から読み込み可能
- ✅ **画像 ID サポート** - ImageService 経由でリソースから画像を取得
- ✅ **カスタマイズ可能なリトライポリシー** - 定数、指数バックオフなど
- ✅ **プレースホルダーとエラー表示のカスタマイズ** - 完全にカスタマイズ可能な UI
- ✅ **キャッシュ管理** - リソースとデータキャッシュの個別管理
- ✅ **iOS 17.0+ および macOS 14.0+ 対応** - クロスプラットフォームサポート

## 必要要件

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## 依存関係

- [swift-api-client](https://github.com/no-problem-dev/swift-api-client) - HTTP クライアント

## 前提条件

このパッケージを `.imageId` で使用する場合、**指定された形式のレスポンスを返す REST API** が必要です。

### 必須 API エンドポイント

1. **GET `/images/{imageId}`** - 画像リソース取得
2. **POST `/images`** - 画像アップロード（multipart/form-data）
3. **DELETE `/images/{imageId}`** - 画像削除

### 必須レスポンス形式（JSON、camelCase）

```json
{
  "id": "img_123",
  "url": "https://example.com/images/photo.jpg"
}
```

> **重要**: レスポンスは **camelCase** である必要があります。

URL 直接指定（`.url` / `.urlString`）の場合は、API サーバーは不要です。

## インストール

### Swift Package Manager

`Package.swift` に以下を追加してください：

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-cached-remote-image.git", from: "1.1.0")
]
```

または Xcode で：
1. File > Add Package Dependencies
2. パッケージ URL を入力: `https://github.com/no-problem-dev/swift-cached-remote-image.git`
3. バージョンを選択: `1.1.0` 以降

## クイックスタート

最もシンプルな使用例：

```swift
import SwiftUI
import CachedRemoteImage

CachedRemoteImage(
    source: .url(URL(string: "https://example.com/image.jpg")!)
)
```

これだけで、画像の読み込み、キャッシュ、デフォルトのローディング表示が行われます。

## 使い方

### 基本的な使用例

```swift
import SwiftUI
import CachedRemoteImage

struct ContentView: View {
    var body: some View {
        CachedRemoteImage(
            source: .url(URL(string: "https://example.com/image.jpg")!)
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

### URL 文字列から直接使用

```swift
CachedRemoteImage(
    source: .urlString("https://example.com/image.jpg")
) { image in
    image.resizable()
}
```

### ImageSource の種類

`CachedRemoteImage` は `ImageSource` enum を通じて柔軟な画像ソースを提供します：

```swift
// 1. URL オブジェクトから
let url = URL(string: "https://example.com/image.jpg")!
CachedRemoteImage(source: .url(url))

// 2. URL 文字列から（自動的に URL に変換）
CachedRemoteImage(source: .urlString("https://example.com/image.jpg"))

// 3. 画像 ID から（ImageService 経由でリソースを取得）
CachedRemoteImage(source: .imageId("img_12345"))
```

> **注意**: `.imageId` を使用する場合は、`ImageService` を環境に注入する必要があります。

### ImageService を使った画像 ID からの取得

```swift
import APIClient
import CachedRemoteImage

// ImageService をセットアップ
@main
struct MyApp: App {
    let imageService: ImageService

    init() {
        let apiClient = APIClientImpl(baseURL: URL(string: "https://api.example.com")!)
        imageService = ImageServiceImpl(
            apiClient: apiClient,
            imagesPath: "/images",
            maxResourceCacheSize: 100
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .imageService(imageService)
        }
    }
}

// 画像 ID で画像を表示
struct ImageView: View {
    let imageId: String

    var body: some View {
        CachedRemoteImage(
            source: .imageId(imageId)
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}
```

## キャッシュ設定

### リソースキャッシュサイズの設定

```swift
// ImageServiceImpl でリソースキャッシュサイズを設定
let imageService = ImageServiceImpl(
    apiClient: apiClient,
    imagesPath: "/images",
    maxResourceCacheSize: 200  // リソースキャッシュ: 最大200エントリ
)
```

### キャッシュクリア

```swift
// リソースキャッシュをクリア
await imageService.clearResourceCache()

// 画像データキャッシュをクリア
await imageService.clearImageCache()

// キャッシュサイズを取得
let cacheSize = await imageService.getCacheSize()
print("Current cache size: \(cacheSize) bytes")
```

### 画像ごとの設定（Configuration）

```swift
// カスタム設定で画像を読み込み
CachedRemoteImage(
    source: .url(imageURL),
    configuration: CachedRemoteImageConfiguration(
        cachePolicy: .useProtocolCachePolicy,
        retryPolicy: .exponential(maxAttempts: 3)
    )
) { image in
    image.resizable()
}
```

利用可能な設定：

- **cachePolicy**: `.useProtocolCachePolicy`, `.reloadIgnoringLocalCacheData`, `.returnCacheDataElseLoad`, `.returnCacheDataDontLoad`
- **retryPolicy**: `.none`, `.constant(maxAttempts:)`, `.exponential(maxAttempts:)`

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。詳細は [LICENSE](LICENSE) ファイルをご覧ください。

## サポート

問題が発生した場合や機能リクエストがある場合は、[GitHub の Issue](https://github.com/no-problem-dev/swift-cached-remote-image/issues) を作成してください。
