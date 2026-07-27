# ``CachedRemoteImage``

リモート画像をメモリ・ディスク二層キャッシュ付きで SwiftUI に表示する軽量パッケージ。

## Overview

**画像の取り方はアプリが与え、キャッシュはパッケージが持つ。**

認証・エンドポイント・レスポンス形式はアプリごとに違い、パッケージが当てられる場所ではない。
一方でキャッシュ・再試行・読み込み状態の管理はどこでも同じで、毎回書き直すものではない。
アプリが実装するのは ``ImageTransport`` の 3 メソッドだけで、残りは ``ImageLibrary`` が引き受ける。

**キャッシュのキーは画像 ID。** 公開 URL を持たない非公開ストレージでも、
バイト列がそのまま二層キャッシュに乗る。

### 組み立て

```swift
import CachedRemoteImage

struct MyImageTransport: ImageTransport {
    let api: MyAPIClient
    func fetch(id: String) async throws -> Data { try await api.getImage(id: id) }
    func upload(_ data: Data, contentType: String) async throws -> String {
        try await api.uploadImage(data, contentType: contentType).id
    }
    func delete(id: String) async throws { try await api.deleteImage(id: id) }
}

let library = try ImageLibrary(transport: MyImageTransport(api: api))

ContentView()
    .imageLibrary(library)
```

メタデータ API が公開 URL を返す形のバックエンドなら、`CachedRemoteImageAPIClient` モジュールの
`URLImageTransport` を渡せば従来どおり動く。

### 表示

``CachedRemoteImage`` は ``ImageSource`` を受け取り、すべての状態をデフォルトビューで処理する。

```swift
// 画像 ID から（ImageTransport 経由）
CachedRemoteImage(source: .imageId("abc123"))

// URL から直接（認証の要らない外部画像。ImageTransport は通らない）
CachedRemoteImage(source: .url(imageURL))

// 画像ビューのみカスタマイズ
CachedRemoteImage(source: .imageId("abc123")) { image in
    image.resizable().scaledToFill()
}
```

### キャッシュと再試行の設定

``ImageLibraryConfiguration`` はライブラリを作るときに一度だけ渡す。
キャッシュも再試行もライブラリが一つ持つ資源で、ビューごとに切り替えられる性質のものではない。
ビューを経由しない取得（``ImageLibrary/prefetch(_:)``）にも同じ設定が効く。

```swift
let library = try ImageLibrary(
    transport: transport,
    configuration: ImageLibraryConfiguration(
        cacheLocation: .appGroup("group.com.example.app"),
        diskCacheSizeLimit: 200 * 1024 * 1024,
        retryPolicy: .exponentialBackoff(maxRetries: 3)
    )
)
```

### ウィジェット

ウィジェット拡張は画像を自分で取れない（非同期取得ができず、認証も持たせるべきではない）。
アプリが ``ImageLibrary/prefetch(_:)`` で App Group に置き、ウィジェットは
``ImageDiskCache`` で同期に読む。この型はネットワークに出る手段を持たない。

```swift
let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))
if let data = cache.imageData(for: item.imageId) { /* 同期で読める */ }
```

### 完全なカスタマイズ

ローディング・エラー・プレースホルダーをすべて差し替える場合はフルイニシャライザを使う。

```swift
CachedRemoteImage(source: .imageId("abc123")) { image in
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

### 画像の出し入れ

- ``ImageTransport``
- ``ImageLibrary``

### キャッシュ

- ``ImageDiskCache``
- ``ImageCacheLocation``
- ``ImageCacheLocationError``

### 画像ソース

- ``ImageSource``

### 設定

- ``ImageLibraryConfiguration``
- ``RetryPolicy``

### ローディング状態

- ``LoadingState``
- ``ImageLoadError``
