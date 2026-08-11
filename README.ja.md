[English](./README.md) | 日本語

# swift-cached-remote-image

取得を自分のアプリの API と認証で行うリモート画像を SwiftUI に表示する。メモリ・ディスクのキャッシュ、リトライ、読み込み状態はこちらで引き受ける。

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![Dependencies](https://img.shields.io/badge/Dependencies-none-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

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

- ✅ **非公開ストレージで使える** — 認証付きでバイト列を返す API が例外ではなく既定の想定
- ✅ **依存ゼロ** — 利用者の解決空間に何も持ち込まないので、アプリ側の HTTP クライアントの世代と衝突しない
- ✅ **画像 ID をキーにした 2 層キャッシュ** — メモリに復号済み画像、ディスクに受け取ったバイト列
- ✅ **ウィジェット対応** — App Group への保存と、ネットワークに出ない同期読み
- ✅ **失敗が呼び出し側に届く** — `print` や黙った `nil` に落とさない
- ✅ **リトライポリシー** — 固定回数・指数バックオフ
- ✅ **プレースホルダーとエラー表示のカスタマイズ** — 完全に差し替え可能

取り方の既定実装は意図的に同梱していない。同梱すると、それを使わない利用者の依存解決まで縛る
（SPM の依存解決はターゲット単位ではなくパッケージ単位のため）。`URLSession` から素で書いても
40 行ほど、アプリが既に HTTP クライアントを持っているなら 15 行で済む。

## クイックスタート

動く部品は 3 つ — アプリが書く transport、ライブラリ 1 つ、そしてビュー。

```swift
import CachedRemoteImage

struct AppImages: ImageTransport {
    let api: MyAPIClient
    func fetch(id: String) async throws -> Data { try await api.imageBytes(id) }
    func upload(_ bytes: Data, contentType: String) async throws -> String { try await api.putImage(bytes, contentType).id }
    func delete(id: String) async throws { try await api.dropImage(id) }
}

let library = try ImageLibrary(transport: AppImages(api: api))   // 起動時に一度
ContentView().imageLibrary(library)                              // ルートで一度

CachedRemoteImage(source: .imageId("img_12345"))                 // 以下どこでも
```

よくある使い方はこれで全部。ビューは環境からライブラリを解決し、メモリ → ディスクの順に見て、
どちらにも無いときだけ transport を呼ぶ。

`ImageLibrary.init` はキャッシュの置き場所を解決できないと throw する（App Group の
entitlement 忘れなど）。設定ミスなので、黙って別の場所に落とすとウィジェットが
何も出せない理由が最後まで分からなくなる。

認証の要らない画像向けに、transport を通らない取得元も 2 つある:

```swift
CachedRemoteImage(source: .url(url))
CachedRemoteImage(source: .urlString("https://example.com/a.jpg"))
```

## URL を返すバックエンド

メタデータ API が公開 URL を返す形なら、transport は 2 段階になる — メタデータを引き、
その URL からバイト列を取る。`ImageTransport` が返すのはどちらの場合も `Data` なので、
`ImageLibrary` から先は同じように動く。

```swift
func fetch(id: String) async throws -> Data {
    let metadata = try await api.imageMetadata(id)
    return try await URLSession.shared.data(from: metadata.url).0
}
```

ID → URL の解決を毎回やるのが惜しければ、transport の中でキャッシュする。
画像バイト列のキャッシュは `ImageLibrary` 側にある。

## ウィジェット

ウィジェット拡張は画像を自分で取れない。WidgetKit のタイムライン生成に非同期の
ネットワーク取得を置く場所が無く、拡張に認証情報を持たせるのも筋が悪い。

そこで、アプリが先読みし、ウィジェットはディスクを同期で読む。

```swift
// アプリ側 — App Group を指定し、同期後に先読みする
let library = try ImageLibrary(transport: AppImages(api: api),
                               configuration: .appGroup("group.com.example.app"))
let failed = await library.prefetch(topItems.map(\.imageId))

// ウィジェット側 — 同じ場所・transport 無し・ネットワーク無し
let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))
let bytes = cache.imageData(for: item.imageId)   // nil = まだ端末に無い
```

`ImageDiskCache` はネットワークに出る手段を持たないので、ウィジェットが取得待ちで固まることが
起こりえない。両側とも同じ `ImageCacheLocation` の値からディレクトリを解決するので、
パスがずれようがない — 別々に組み立てると 1 文字違うだけでウィジェットが無表示になる。

## キャッシュの設定

設定はビューごとではなくライブラリ単位。キャッシュは共有された 1 つの資源で、
ビューが持つものではない。たいていはプリセットで足りる:

```swift
let library = try ImageLibrary(transport: transport, configuration: .withRetry)
```

`.standard` は Caches 配下・再試行なし、`.withRetry` は指数バックオフ付き、
`.appGroup(_:subdirectory:)` はウィジェットが読める場所へ移す。
細かい調整は `ImageLibraryConfiguration` で行う。

- **メモリ**は復号済みの画像を持つ。スクロール中に効くのは復号のスキップで、ファイル読み込みのスキップではない
- **ディスク**は受け取ったバイト列をそのまま持つ。再エンコードしないので PNG の透過も残り、
  ウィジェットが読むのも実物になる。上限を超えたぶんは古い順に消える
  （App Group は OS が消してくれないので、上限は入れる側が決める必要がある）

## エラー

起こりうる失敗はすべて `ImageLoadError` としてエラービューに届く — ライブラリ未注入、
URL にできない文字列、transport の失敗、復号できないバイト列。原因は説明文で運ぶ。
元のエラー型を持たせると `Sendable` と `Equatable` を諦めることになり、
そして型で分岐したい側（トークンを取り直す・サインアウトさせる）は transport を書いた側なので、
自分が投げたエラーをそこで捕まえられる。

書き込み経路（`add` / `remove`）は transport が投げた型をそのまま通す。

## ドキュメント

📚 **[API リファレンスとガイド](https://no-problem-dev.github.io/swift-cached-remote-image/documentation/cachedremoteimage/)**
— `URLSession` で書いた transport の全文、ウィジェット構成の手順、設定項目の全一覧。

## インストール

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-cached-remote-image.git", from: "4.0.2")
]
```

ターゲットに足すのは 1 つだけ:

```swift
.product(name: "CachedRemoteImage", package: "swift-cached-remote-image"),
```

4.0.0 は依存解決が通らないが、`from: "4.0.2"` なら選ばれない。
`Package.resolved` に 4.0.0 が残っている場合は消して解決し直す。

## 必要要件

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されている。詳細は [LICENSE](LICENSE) ファイルを参照。
