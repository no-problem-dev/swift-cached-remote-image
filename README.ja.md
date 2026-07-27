[English](./README.md) | 日本語

# swift-cached-remote-image

SwiftUI でリモート画像をキャッシュ付きで表示するパッケージ

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

📚 **[完全なドキュメント](https://no-problem-dev.github.io/swift-cached-remote-image/documentation/cachedremoteimage/)**

## 概要

**画像の取り方はアプリが与え、キャッシュはパッケージが持つ。**

認証・エンドポイント・レスポンス形式はアプリごとに違い、パッケージが当てられる場所ではない。
一方でキャッシュ・再試行・SwiftUI の読み込み状態はどこでも同じで、毎回書き直すものではない。

だからアプリが実装するのは 3 メソッドだけ:

```swift
public protocol ImageTransport: Sendable {
    func fetch(id: String) async throws -> Data
    func upload(_ data: Data, contentType: String) async throws -> String  // → image id
    func delete(id: String) async throws
}
```

これを `ImageLibrary` に渡すと、**画像 ID をキーにした** 2 層キャッシュ・再試行・先読み・
ウィジェット向けの同期読み・`CachedRemoteImage` ビューが付いてくる。

メタデータ API が公開 URL を返す形のバックエンドなら、`URLImageTransport` を同梱しているので
transport を書く必要はない。

### 主な機能

- ✅ **非公開ストレージで使える** — 認証付きでバイト列を返す API が例外ではなく既定の想定
- ✅ **画像 ID をキーにした 2 層キャッシュ** — メモリに復号済み画像、ディスクに受け取ったバイト列
- ✅ **ウィジェット対応** — App Group への保存と、ネットワークに出ない同期読み
- ✅ **層を守れるモジュール分割** — ビュー側のモジュールは `APIClient` に依存しない
- ✅ **失敗が呼び出し側に届く** — `print` や黙った `nil` に落とさない
- ✅ **リトライポリシー** — 固定回数・指数バックオフ
- ✅ **プレースホルダーとエラー表示のカスタマイズ** — 完全に差し替え可能
- ✅ **iOS 17.0+ / macOS 14.0+**

### モジュール

| モジュール | 中身 | 依存 |
|---|---|---|
| `CachedRemoteImage` | ビュー・`ImageTransport`・`ImageLibrary`・`ImageDiskCache`・設定 | なし |
| `CachedRemoteImageAPIClient` | `URLImageTransport`（メタデータ API → URL → URLSession） | `APIClient` |

分けてあるのは、画像を描くだけの Presentation 層が HTTP クライアントを巻き込まないようにするため。

## 必要要件

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## インストール

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-cached-remote-image.git", from: "4.0.0")
]
```

使うモジュールを依存に足す:

```swift
.product(name: "CachedRemoteImage", package: "swift-cached-remote-image"),
// 同梱の URL ベース transport を使う場合だけ
.product(name: "CachedRemoteImageAPIClient", package: "swift-cached-remote-image"),
```

## クイックスタート

### 1. transport を実装する

```swift
import CachedRemoteImage

struct MyImageTransport: ImageTransport {
    let api: MyAPIClient

    func fetch(id: String) async throws -> Data {
        try await api.getImage(id: id)
    }

    func upload(_ data: Data, contentType: String) async throws -> String {
        try await api.uploadImage(data, contentType: contentType).id
    }

    func delete(id: String) async throws {
        try await api.deleteImage(id: id)
    }
}
```

### 2. ライブラリを作って注入する

```swift
@main
struct MyApp: App {
    private let library: ImageLibrary

    init() throws {
        library = try ImageLibrary(transport: MyImageTransport(api: api))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .imageLibrary(library)
        }
    }
}
```

`ImageLibrary.init` はキャッシュの置き場所を解決できないと throw する（App Group の
entitlement 忘れなど）。設定ミスなので、黙って別の場所に落とすとウィジェットが
何も出せない理由が最後まで分からなくなる。

### 3. 表示する

```swift
CachedRemoteImage(source: .imageId("img_12345"))

CachedRemoteImage(source: .imageId("img_12345"), contentMode: .fill) { image in
    image.resizable()
} placeholder: {
    Color.gray.opacity(0.2)
}
```

`ImageSource` は 3 種類:

```swift
CachedRemoteImage(source: .imageId("img_12345"))                        // ImageTransport 経由
CachedRemoteImage(source: .url(url))                                    // 素の URLSession
CachedRemoteImage(source: .urlString("https://example.com/a.jpg"))      // 素の URLSession
```

`.url` / `.urlString` は transport を通らない。URL は宛先を自分で名乗っているので、
アプリ固有の取り方を挟む余地がない。認証の要らない画像（検索結果のサムネイルなど）に使う。

## URL を返すバックエンド

`GET /images/{id}` が `{ "id": ..., "url": ... }` を返す形なら、同梱の transport を渡す:

```swift
import CachedRemoteImageAPIClient

let transport = URLImageTransport(apiClient: apiClient, imagesPath: "/v1/images")
let library = try ImageLibrary(transport: transport)
```

必要なエンドポイント:

| エンドポイント | ボディ | レスポンス |
|---|---|---|
| `GET {imagesPath}/{id}` | — | `{ "id": "img_123", "url": "https://..." }` |
| `POST {imagesPath}` | `multipart/form-data`（フィールド名は既定 `file`） | 同じ形 |
| `DELETE {imagesPath}/{id}` | — | — |

フィールド名は `URLImageTransport(… uploadFieldName: "image")` で変えられる。

ID → URL の解決は transport 内で LRU キャッシュする。画像バイト列のキャッシュは
`ImageLibrary` 側にあるので、どんな transport でも同じように効く。

## ウィジェット

ウィジェット拡張は画像を自分で取れない。WidgetKit のタイムライン生成に非同期の
ネットワーク取得を置く場所が無く、拡張に認証情報を持たせるのも筋が悪い。

そこで、アプリが先読みし、ウィジェットはディスクを同期で読む。

**アプリ側 — App Group を指定し、同期後に先読みする:**

```swift
let library = try ImageLibrary(
    transport: MyImageTransport(api: api),
    configuration: .appGroup("group.com.example.app")
)

let failed = await library.prefetch(topItems.map(\.imageId))
```

**ウィジェット側 — 同じ場所・transport 無し・ネットワーク無し:**

```swift
import CachedRemoteImage

let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))

if let data = cache.imageData(for: item.imageId), let image = UIImage(data: data) {
    Image(uiImage: image).resizable()
} else {
    Text(item.emoji)          // 無いときに落ちる先を必ず用意する
}
```

`ImageDiskCache` はネットワークに出る手段を持たないので、ウィジェットが取得待ちで固まることが
起こりえない。`imageData(for:)` の `nil` は「まだ端末に無い」だけを意味する。

両側とも同じ `ImageCacheLocation` の値からディレクトリを解決するので、パスがずれようがない。
別々に組み立てると、1 文字違うだけでウィジェットが無表示になる。

## キャッシュの設定

```swift
let library = try ImageLibrary(
    transport: transport,
    configuration: ImageLibraryConfiguration(
        cacheLocation: .appGroup("group.com.example.app"),
        diskCacheSizeLimit: 200 * 1024 * 1024,
        memoryCountLimit: 200,
        memoryCostLimit: 100 * 1024 * 1024,
        retryPolicy: .exponentialBackoff(maxRetries: 3)
    )
)
```

プリセット: `.standard` / `.withRetry` / `.appGroup(_:subdirectory:)`。

設定はビューごとではなくライブラリ単位。キャッシュは共有された 1 つの資源で、
ビューが持つものではない。

- **メモリ**は復号済みの画像を持つ。スクロール中に効くのは復号のスキップで、ファイル読み込みのスキップではない
- **ディスク**は受け取ったバイト列をそのまま持つ。再エンコードしないので PNG の透過も残り、
  ウィジェットが読むのも実物になる。`diskCacheSizeLimit` を超えたぶんは古い順に消える
  （App Group は OS が消してくれないので、上限は入れる側が決める必要がある）

```swift
library.clearMemoryCache()
library.clearDiskCache()
let bytes = library.diskCacheSize()
```

## エラー

```swift
public enum ImageLoadError: Error, Equatable, Sendable {
    case libraryNotConfigured          // 環境に .imageLibrary(_:) が無い
    case invalidURL(String)
    case transportFailed(reason: String)
    case notAnImage(byteCount: Int)
}
```

どれもエラービューに届く。原因は説明文で運ぶ — 元のエラー型を持たせると `Sendable` と
`Equatable` を諦めることになり、そして型で分岐したい側（トークンを取り直す・サインアウトさせる）は
transport を書いた側なので、自分が投げたエラーをそこで捕まえられる。

書き込み経路（`add` / `remove`）は transport が投げた型をそのまま通す。

## 3.x からの移行

`ImageService` / `ImageServiceImpl` は廃止した。破壊的変更の一覧と移行手順は
[CHANGELOG.md](CHANGELOG.md) を参照。

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されている。詳細は [LICENSE](LICENSE) ファイルを参照。

## サポート

問題が発生した場合や機能リクエストがある場合は、[GitHub の Issue](https://github.com/no-problem-dev/swift-cached-remote-image/issues) を作成する。
