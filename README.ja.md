[English](./README.md) | 日本語

# swift-cached-remote-image

SwiftUI でリモート画像をキャッシュ付きで表示するパッケージ

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![Dependencies](https://img.shields.io/badge/Dependencies-none-brightgreen.svg)
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

### このパッケージは依存を持たない

取り方の既定実装は**同梱しない**。書くのはアプリ側で、下の例のとおり 30 行ほどで済む。

同梱しないのは、同梱すると利用者の依存解決を縛るから。4.0 の最初の版では、HTTP クライアントを
使う既定 transport を別ターゲットに置いていた。ビューだけ使う人には依存が届かない、と考えていた。
**これは効かない。** SPM の依存解決は**パッケージ単位**で、ターゲット単位ではない。
使わないターゲットのために宣言した依存も、利用者の解決空間にそのまま入る。
実際、別世代の HTTP クライアントを既に使っているアプリが、このパッケージを足しただけで
バージョン解決に失敗した — 使っていないターゲットの依存が原因で。

分けるならパッケージごと分けるしかない。そして `ImageTransport` は 3 メソッドで、アプリが既に
持っている HTTP スタックの上に書けば数行で終わる。使われない実装を同梱して利用者の依存グラフに
制約を持ち込む釣り合いではない。

### 主な機能

- ✅ **非公開ストレージで使える** — 認証付きでバイト列を返す API が例外ではなく既定の想定
- ✅ **依存ゼロ** — 利用者の解決空間に何も持ち込まないので、アプリ側の HTTP クライアントの世代と衝突しない
- ✅ **画像 ID をキーにした 2 層キャッシュ** — メモリに復号済み画像、ディスクに受け取ったバイト列
- ✅ **ウィジェット対応** — App Group への保存と、ネットワークに出ない同期読み
- ✅ **失敗が呼び出し側に届く** — `print` や黙った `nil` に落とさない
- ✅ **リトライポリシー** — 固定回数・指数バックオフ
- ✅ **プレースホルダーとエラー表示のカスタマイズ** — 完全に差し替え可能
- ✅ **iOS 17.0+ / macOS 14.0+**

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

ターゲットに足すのは 1 つだけ:

```swift
.product(name: "CachedRemoteImage", package: "swift-cached-remote-image"),
```

## クイックスタート

### 1. transport を書く

想定している既定の形は**非公開ストレージ** — 認証付きで画像バイト列を直接返す API。
`ImageTransport` に必要なのは 3 メソッドで、キャッシュも再試行もこの中には要らない
（外側の `ImageLibrary` が持つ）。呼ばれるのは「メモリにもディスクにも無い」と確定した時だけ。

```swift
import CachedRemoteImage
import Foundation

struct APIImageTransport: ImageTransport {
    let baseURL: URL
    let accessToken: @Sendable () async -> String

    func fetch(id: String) async throws -> Data {
        let request = await authorized("images/\(id)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(response)
        return data
    }

    func upload(_ imageData: Data, contentType: String) async throws -> String {
        var request = await authorized("images", method: "POST")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: imageData)
        try Self.checkOK(response)
        return try JSONDecoder().decode(UploadedImage.self, from: data).id
    }

    func delete(id: String) async throws {
        let request = await authorized("images/\(id)", method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(response)
    }

    private func authorized(_ path: String, method: String = "GET") async -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    private struct UploadedImage: Decodable {
        let id: String
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
```

アプリが既に HTTP クライアントを持っているなら、3 メソッドはその上に載せるだけになる:

```swift
struct APIImageTransport: ImageTransport {
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

投げるエラーの型は自由。表示経路では `ImageLoadError.transportFailed(reason:)` に包み直されるが、
説明文（`localizedDescription`）は保たれる。型で分岐したい処理 — 認証切れを検知して
サインインに送る、など — は transport を書いた側で捕まえる。自分が投げたエラーなので、
そこが一番情報を持っている。

### 2. ライブラリを作って注入する

```swift
@main
struct MyApp: App {
    private let library: ImageLibrary

    init() throws {
        library = try ImageLibrary(transport: APIImageTransport(api: api))
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

メタデータ API が公開 URL を返す形なら、transport は 2 段階になる — メタデータを引き、
その URL からバイト列を取る。`ImageTransport` が返すのはどちらの場合も Data なので、
`ImageLibrary` から先は同じように動く。

```swift
struct MetadataImageTransport: ImageTransport {
    let baseURL: URL

    func fetch(id: String) async throws -> Data {
        let (json, _) = try await URLSession.shared.data(from: baseURL.appending(path: "images/\(id)"))
        let metadata = try JSONDecoder().decode(ImageMetadata.self, from: json)
        let (bytes, _) = try await URLSession.shared.data(from: metadata.url)
        return bytes
    }

    // upload / delete も同じ形（POST / DELETE して、返ってきた JSON から id を読む）

    private struct ImageMetadata: Decodable {
        let id: String
        let url: URL
    }
}
```

ID → URL の解決を毎回やるのが惜しければ、transport の中でキャッシュする。
画像バイト列のキャッシュは `ImageLibrary` 側にあるので、transport が持つのは
自分の関心事（URL の解決）だけでいい。

## ウィジェット

ウィジェット拡張は画像を自分で取れない。WidgetKit のタイムライン生成に非同期の
ネットワーク取得を置く場所が無く、拡張に認証情報を持たせるのも筋が悪い。

そこで、アプリが先読みし、ウィジェットはディスクを同期で読む。

**アプリ側 — App Group を指定し、同期後に先読みする:**

```swift
let library = try ImageLibrary(
    transport: APIImageTransport(api: api),
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
