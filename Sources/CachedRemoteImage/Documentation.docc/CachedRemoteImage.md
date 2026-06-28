# ``CachedRemoteImage``

リモート画像をメモリ・ディスク二層キャッシュ付きで SwiftUI に表示する軽量パッケージ。

## Overview

`CachedRemoteImage` は iOS 17+ / macOS 14+ 向けの SwiftUI 画像ローディングパッケージ。
ネットワーク越しの画像をメモリキャッシュとディスクキャッシュの二層で管理し、宣言的な API で画像表示のライフサイクル全体 — プレースホルダー・ローディング・成功・エラー — を処理する。

### 最も簡単な使い方

``CachedRemoteImage`` は ``ImageSource`` を受け取り、すべての状態をデフォルトビューで処理する。

```swift
import CachedRemoteImage

// URL から直接表示（プレースホルダー・ローディング・エラーはデフォルト）
CachedRemoteImage(source: .url(imageURL))

// 画像 ID から取得（ImageService を通じてメタデータ → 画像の 2 段階取得）
CachedRemoteImage(source: .imageId("abc123"))

// 画像ビューのみカスタマイズ
CachedRemoteImage(source: .url(imageURL)) { image in
    image.resizable().scaledToFill()
}
```

### ImageService の注入

画像の取得・キャッシュ・アップロードは ``ImageService`` プロトコルで抽象化されている。
`View.imageService(_:)` モディファイアでルートビューに一度だけ注入する。

```swift
import CachedRemoteImage
import APIClient

let apiClient = APIClientImpl(
    baseURL: URL(string: "https://api.example.com")!
)
let imageService = ImageServiceImpl(
    apiClient: apiClient,
    imagesPath: "/v1/images",
    maxResourceCacheSize: 200
)

ContentView()
    .imageService(imageService)
```

### キャッシュとリトライの設定

``CachedRemoteImageConfiguration`` でキャッシュ戦略とリトライ動作を制御する。
パッケージには `standard`（全キャッシュ）・`noCache`・`withRetry` の 3 つのプリセットが用意されている。

```swift
// ネットワーク不安定環境向け：指数バックオフでリトライ
CachedRemoteImage(
    source: .imageId("abc123"),
    configuration: .withRetry
)

// カスタム設定：メタデータのみキャッシュ、最大 3 回リトライ
CachedRemoteImage(
    source: .url(imageURL),
    configuration: CachedRemoteImageConfiguration(
        cachePolicy: .metadataOnly,
        retryPolicy: .exponentialBackoff(maxRetries: 3)
    )
)
```

### 完全なカスタマイズ

ローディング・エラー・プレースホルダーをすべて差し替える場合はフルイニシャライザを使う。

```swift
CachedRemoteImage(
    source: .url(imageURL),
    configuration: .withRetry
) { image in
    image.resizable().scaledToFill()
} loading: {
    ProgressView("読み込み中...")
} error: { err in
    VStack {
        Image(systemName: "xmark.circle")
        Text(err.localizedMessage).font(.caption)
    }
} placeholder: {
    Color.gray.opacity(0.2)
}
```

## Topics

### ビュー

- ``CachedRemoteImage``

### デフォルト状態ビュー

- ``DefaultLoadingView``
- ``DefaultErrorView``
- ``DefaultPlaceholderView``

### 画像サービス

- ``ImageService``
- ``ImageServiceImpl``

### 画像ソース

- ``ImageSource``
- ``ImageResource``

### 設定

- ``CachedRemoteImageConfiguration``
- ``CachePolicy``
- ``RetryPolicy``

### ローディング状態

- ``LoadingState``
- ``ImageLoadError``
