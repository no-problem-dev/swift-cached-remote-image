# Changelog

このプロジェクトのすべての重要な変更は、このファイルに記録されます。

このフォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいており、
このプロジェクトは [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

## [未リリース]

なし

## [4.0.2] - 2026-08-02

**プライバシーマニフェストを同梱。** 取り込む側が肩代わりして申告する必要がなくなる。

`ImageDiskCache` は容量超過のときに古い順で捨てるため `.contentModificationDateKey` を読む。
これは Apple が理由の申告を求める API（ファイル日時）で、申告が無いと利用者に
ITMS-91053 の警告が届く。

これまでは取り込む側のアプリが自分の `PrivacyInfo.xcprivacy` に書くしかなかった。
それは「このパッケージが何の API を呼ぶか」を利用者が知っている前提で、
キャッシュの実装を読ませることになる。**自分で申告すれば利用者は何も知らなくてよい。**

- 申告は 1 件だけ（ファイル日時 / `C617.1` = アプリまたは App Group コンテナの中）
- 収集は無い。画像を取りに行く実装すら持たない（`ImageTransport` は protocol）
- `.copy` で入れる（`.process` だと plist として最適化されうる）

利用者側の対応は不要。取り込む版を上げるだけで、アプリ側の申告が欠けても補われる。

## [4.0.1] - 2026-07-27

**4.0.0 を使える状態にする修正。** パッケージを依存ゼロにした。

公開済みのタグは差し替えない方針なので、**4.0.0 は使えない版としてそのまま残り、
この 4.0.1 が直す**。差し替えると、fetch 済みのキャッシュや利用者の `Package.resolved` に
残った revision と中身が食い違い、「解決できない」「取得したものが違う」という
原因の分かりにくい壊れ方をする。

### なぜ 4.0.0 が使えなかったか

4.0.0 は取り方の既定実装（`APIClient` を使う `URLImageTransport`）を
`CachedRemoteImageAPIClient` という別ターゲットに置いた。ビューだけを使う利用者は
`APIClient` を巻き込まない、という狙いだった。

**それは効かない。SPM の依存解決はパッケージ単位**なので、使わないターゲットのために
宣言した依存も利用者の解決空間に入る。`swift-api-client` 1.x 世代のアプリは 4.0.0 を
取り込めなかった:

```
error: Dependencies could not be resolved because root depends on
'swift-authentication' 1.0.0..<2.0.0 and root depends on 'swift-cached-remote-image' 4.0.0..<5.0.0.
'swift-cached-remote-image' >= 4.0.0 practically depends on 'swift-api-client' 3.0.0..<4.0.0
```

分けるならパッケージごと分けるしかない。そして `URLImageTransport` は `ImageTransport` の
3 メソッドを HTTP で埋めるだけのもので、アプリが既に持っている HTTP スタックで書けば
30 行に満たない。使われない実装を同梱して利用者の依存グラフに制約を持ち込む釣り合いではない。

### 変更

- `CachedRemoteImageAPIClient` ターゲットと `URLImageTransport` を**削除**した。
  **取り方の既定実装は同梱しない** — `ImageTransport` は利用者が自分の HTTP スタックで実装する
- パッケージの依存は**ゼロ**になった（DocC プラグインはビルド時のみ）
- ターゲットに足す product は `CachedRemoteImage` の 1 つだけになった
- テストは 72 → 52。削除したターゲットに属する 20 件（multipart 組み立て・URL 解決の
  LRU）が一緒に無くなった。残る 52 件はキャッシュ・再試行・transport 差し替えの回帰で、
  すべて green
- README / DocC を実態に合わせた。取り方は利用者が書くものになったので、
  `ImageTransport` の実装例（非公開ストレージ・認証付きでバイト列を返す API）を主役にした

### なぜ major ではなく patch か

product の削除は厳密には破壊的変更にあたる。しかし **4.0.0 は依存解決が通らないので
実質の利用者がいない**（解決できた利用者だけが `CachedRemoteImageAPIClient` を使えたが、
解決できた環境は存在しない）。壊れた版を直すために major をもう 1 つ重ねると、
版番号だけが進んで実態と離れる。

### 4.0.0 を取り込もうとしていた場合

そのまま `4.0.1` 以上に上げる。`Package.resolved` に 4.0.0 が残っていれば消して解決し直す。

## [4.0.0] - 2026-07-27

> ⚠️ **この版は依存解決が通らない。4.0.1 以降を使うこと。**
> 下の「破壊的変更 2」のモジュール分割が原因で、この版は取り込めない（理由は 4.0.1 の項）。
> 以下はこの版が出荷した内容の記録であり、現在の API ではない。

責務の向きを逆にした。3.x はパッケージが「画像の取り方」を決め打ちし、キャッシュを
その内側に隠していた。4.0 は**アプリが取り方を与え、キャッシュはパッケージが持つ**。

### なぜ変えたか

3.1.0 で `ImageService.loadImage(imageId:)` を足したが、実態は**入口だけで中身が無かった**。

- `ImageServiceImpl` はこの要件を override しておらず、既定実装は
  `getImageResource` → URL → `loadImage(from:)` に委ねる。公開 URL を持たない
  バックエンドでは成立しない
- 2 層キャッシュのキーが **URL 文字列**だったので、利用者が自分で書いた
  `loadImage(imageId:)` からはキャッシュに一切乗らなかった

結果、非公開ストレージを使う利用者は、キャッシュを自分で書き直し、
`getImageResource` は「URL は無い」と throw し、`uploadImage` は実在しない URL を
組み立てて返す — という、プロトコルを満たすためだけの実装を書くことになっていた。
同じ形のバックエンドが 2 つ続いた時点で、これは例外ではなく**既定の想定が逆**だという証拠になる。

### ⚠️ 破壊的変更

#### 1. `ImageService` を廃止し、`ImageTransport` + `ImageLibrary` に置き換えた

アプリが実装するのは 3 メソッドの `ImageTransport` だけになった。
2 層キャッシュ・再試行・SwiftUI ビューへの供給は具象型 `ImageLibrary` が引き受ける。

```swift
public protocol ImageTransport: Sendable {
    func fetch(id: String) async throws -> Data
    func upload(_ data: Data, contentType: String) async throws -> String  // → image id
    func delete(id: String) async throws
}
```

**キャッシュのキーは画像 ID になった。** バイト列経路がそのまま 2 層キャッシュに乗る。

- 削除: `ImageService` / `ImageServiceImpl` / `ImageResource`
- 追加: `ImageTransport` / `ImageLibrary` / `ImageDiskCache` /
  `ImageCacheLocation` / `ImageLibraryConfiguration`
- 環境値と修飾子: `\.imageService` → `\.imageLibrary`、`.imageService(_:)` → `.imageLibrary(_:)`

移行（非公開ストレージ・バイト列を返す API の場合）:

```swift
// Before: ImageService の 9 要件を満たすために ~130 行。半分がメモリキャッシュの手書き
struct MyImageService: ImageService {
    func getImageResource(imageId: String) async throws -> ImageResource {
        throw ImageServiceError.noPublicURL       // URL が無いことを表明するためだけの実装
    }
    func uploadImage(imageData: Data, contentType: String) async throws -> ImageResource {
        ImageResource(id: uploaded.id, url: placeholderURL(for: uploaded.id))  // 実在しない URL
    }
    // + loadImage(imageId:) / loadImage(from:) / deleteImage / clearResourceCache /
    //   clearImageCache / diskCacheSize / 自前のメモリキャッシュ actor
}

// After: 3 メソッド
struct MyImageTransport: ImageTransport {
    let api: MyAPI
    func fetch(id: String) async throws -> Data { try await api.getImage(id: id) }
    func upload(_ data: Data, contentType: String) async throws -> String {
        try await api.uploadImage(data, contentType: contentType).id
    }
    func delete(id: String) async throws { try await api.deleteImage(id: id) }
}

let library = try ImageLibrary(transport: MyImageTransport(api: api))
ContentView().imageLibrary(library)
```

移行（URL を返す REST API の場合）— `CachedRemoteImageAPIClient` の
`URLImageTransport` を渡すと従来と同じ経路で動く:

```swift
// Before
let service = ImageServiceImpl(apiClient: apiClient, imagesPath: "/images", maxResourceCacheSize: 100)
ContentView().imageService(service)

// After
let transport = URLImageTransport(apiClient: apiClient, imagesPath: "/images", maxURLCacheSize: 100)
let library = try ImageLibrary(transport: transport)
ContentView().imageLibrary(library)
```

#### 2. モジュールを 2 つに分けた

`CachedRemoteImage` が `APIClient` に依存しなくなった。ビューを使うだけの
Presentation 層が Infrastructure（HTTP クライアント）を巻き込まずに済む。

| モジュール | 中身 | 依存 |
|---|---|---|
| `CachedRemoteImage` | ビュー・`ImageTransport`・`ImageLibrary`・`ImageDiskCache`・設定 | なし |
| `CachedRemoteImageAPIClient` | `URLImageTransport`（メタデータ API → URL → URLSession） | `APIClient` |

`URLImageTransport` を使う場合は `CachedRemoteImageAPIClient` も依存に足す:

```swift
.product(name: "CachedRemoteImage", package: "swift-cached-remote-image"),
.product(name: "CachedRemoteImageAPIClient", package: "swift-cached-remote-image"),
```

#### 3. 設定はビューごとではなくライブラリ単位になった

`CachedRemoteImageConfiguration` を廃止し、`ImageLibraryConfiguration` にした。
`CachedRemoteImage(source:configuration:)` の `configuration` 引数も無くなった。

キャッシュも再試行もライブラリが一つ持つ資源で、ビューごとに切り替えられる性質ではない。
実際 `cachePolicy` はどこからも読まれておらず、**渡しても何も起きなかった**。

```swift
// Before（cachePolicy は無効。retryPolicy はビューごと）
CachedRemoteImage(source: .imageId(id), configuration: .withRetry)

// After（ライブラリを作るときに一度だけ。ビューを経由しない取得にも効く）
let library = try ImageLibrary(transport: transport, configuration: .withRetry)
```

- 削除: `CachePolicy`（`.all` / `.metadataOnly` / `.imageOnly` / `.none`）— 実装されていなかった
- 削除: `CachedRemoteImageConfiguration`
- `RetryPolicy` は残る（`ImageLibraryConfiguration` に移動）

#### 4. ディスクキャッシュの保存先を注入できるようにした

App Group を指定できる。ウィジェット拡張が画像を読むために必要。

```swift
let library = try ImageLibrary(transport: transport, configuration: .appGroup("group.com.example.app"))
```

置き場所を解決できない場合、`ImageLibrary.init` は **throw する**（`ImageCacheLocationError`）。
黙って別の場所に落とすと、ウィジェットが何も出せない理由が最後まで分からなくなるため。
`ImageLibrary` の生成に `try` が要るようになった。

#### 5. ディスクには受け取ったバイト列をそのまま保存する

3.x は `UIImage` に復号してから JPEG q0.8 で再エンコードして書いていた。
取得済みのバイト列を捨てて劣化した別のバイト列を作る動きで、PNG の透過も失われていた。
4.0 は受け取った `Data` をそのまま書く。ウィジェットが読むのも実物のバイト列になる。

キャッシュのファイル名も変わった（キーの SHA-256）。**3.x のディスクキャッシュは読めない。**
初回起動時にキャッシュミスとして取り直されるだけで、消す処理は要らない。

#### 6. アップロードが multipart になった

`UploadImageContract` は Base64-in-JSON をやめ、`multipart/form-data` を送る。
33% の膨張と全量のメモリ載せが無くなる。フィールド名は `URLImageTransport` の
`uploadFieldName`（既定 `"file"`）で変えられる。

**サーバー側が Base64 JSON（`image_data` / `content_type`）を期待している場合は、
multipart を受けるように直す必要がある。**

#### 7. 失敗の伝え方

- `ImageLoadError` の case を入れ替えた: `.libraryNotConfigured` / `.invalidURL` /
  `.transportFailed(reason:)` / `.notAnImage(byteCount:)`
  （削除: `.metadataFetchFailed` / `.downloadFailed` / `.networkError` / `.unknown`）
- `ImageLibrary` が未注入のとき、3.x は `print` して素通りしていた。
  4.0 は `.failure(.libraryNotConfigured)` になり、エラービューに出る
- `loadImage(from:)` の `catch { print; return nil }` を廃止。取得の失敗は throw する
- `ImageResourceDTO` の URL 変換は `fatalError` をやめて throw する。
  サーバーが壊れた値を返しただけでアプリが落ちることは無くなった
- 表示経路（`image(for:)` / `image(from:)` / `imageData(for:)`）は `ImageLoadError` に包む。
  書き込み経路（`add` / `remove`）は transport が投げた型をそのまま通す

#### 8. キャッシュ管理 API

```swift
// Before                              // After
await service.clearResourceCache()     library.clearMemoryCache()
await service.clearImageCache()        library.clearDiskCache()
await service.diskCacheSize()          library.diskCacheSize()
```

`async` ではなくなった（ファイル操作は同期で、待つものが無い）。

### 追加

- `ImageDiskCache` — ディスクを**同期で**読む型。ネットワークに出る手段を持たない。
  WidgetKit のタイムライン生成のための入口

  ```swift
  let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))
  if let data = cache.imageData(for: item.imageId) { /* 同期で読める */ }
  ```

- `ImageLibrary.cachedImageData(for:)` — アプリ本体側の同じ入口
- `ImageLibrary.prefetch(_:)` — 表示予定の画像を先に端末へ落とす。
  ウィジェットは認証を持てないので、アプリ側が置いておく。取れなかった ID を返す
- `ImageCacheLocation` — 保存場所を値として渡す。アプリとウィジェットが
  同じ値から解決するので、パスの綴りがずれようがない
- ディスクキャッシュの上限（既定 100MB、超過分は古い順に削除）。
  App Group は OS が消さない場所なので、上限を持たないと端末の空きが戻らない

### 変更

- `ImageSource` は `Hashable` にも準拠
- `RetryPolicy.delay(for:)` は `async` をやめた（純粋な計算だった）
- 再試行の対象は取得の失敗だけになった。復号できないバイト列（`.notAnImage`）は
  再試行しない。同じバイト列を何度復号しても結果は変わらないため

### テスト

31 → 72。設計変更で意味を失ったテストは消し、新しい経路
（ID キーのキャッシュ・同期読み・transport の差し替え・上限・multipart）に回帰を足した。

## [3.1.0] - 2026-07-20

### 追加

- `ImageService.loadImage(imageId:)` を追加。公開 URL を持たないバックエンド
  （非公開ストレージ・認証付きで画像バイト列を返す API）向けの読み込み経路。
  メタデータに URL が無い場合、`getImageResource` → `loadImage(from:)` の 2 段階は
  成立しないため、この要件を実装して直接バイト列を取りに行ける。

  既定実装は従来どおりメタデータから URL を引いて `loadImage(from:)` に委ねるので、
  **URL を返せるバックエンドの実装者は何もしなくてよい**（非破壊の追加）。

  同じ機能は 1.x 系で 1.1.6（2026-07-20）として追加済みだったが、2.0.0 以降の系列には
  移植されておらず、`loadImage(imageId:)` を使う利用者が 1.x に取り残されていた。

### 変更

- 1.x 系の実装では既定実装が `try?` でメタデータ取得の失敗を握りつぶして `nil` を返しており、
  呼び出し側は原因を失ったまま「ダウンロード失敗」として扱っていた。実際には
  ダウンロードに到達すらしていない。本系列では要件を `throws` にして**原因をそのまま伝播**する。
  `nil` は「取得はできたが画像にならなかった」に意味を限定した。
  非 throwing の実装でも要件は満たせるため、既存の準拠型に変更は要らない。

## [3.0.0] - 2026-07-19

### ⚠️ 破壊的変更

- swift-api-client の依存を `from: "3.0.0"` に更新（ファミリーの api-client 世代統一）。
  本パッケージは `AuthTokenProvider` のシンボルを直接使っていないためソース変更は無いが、
  依存の major が上がるため消費者の解決グラフに影響する。

## [2.0.0] - 2026-07-19

### ⚠️ 破壊的変更

- swift-api-client の依存を `from: "2.3.1"` に更新（ピン世代統一）。
  APIInput の Codec seam 化に追随。
- LRU / 二層キャッシュ / ImageService の実テストを 28 件追加
  （従来はプレースホルダのみだった）。

## [1.1.5] - 2026-01-18

### 変更
- 画像アップロードをマルチパートフォームデータからBase64エンコードJSONボディ形式に変更
- `UploadImageRequestBody` 構造体を追加してリクエストボディを構造化
- `ImageService` プロトコルに `uploadImage(imageData:contentType:)` メソッドを追加（コンテンツタイプ指定可能）

### 破壊的変更
- サーバー側がBase64 JSONボディを期待する形式に対応するための変更

## [1.1.4] - 2026-01-08

### 変更
- `ImageRepository` と `ImageServiceImpl` を `APIExecutable` プロトコルに対応するジェネリック実装に変更
- 従来の `APIEndpoint` + `request()` パターンから `APIContract` + `execute()` パターンへ移行
- 型安全な API 契約（`GetImageResourceContract`, `UploadImageContract`, `DeleteImageContract`）を追加
- swift-tools-version を 6.0 から 6.2 に更新
- `Package.resolved` を gitignore に追加してバージョン管理から除外

## [1.1.3] - 2025-11-13

### 変更
- パッケージ依存関係の記法を明示的な `.upToNextMajor(from:)` に変更
  - `swift-api-client`: `from: "1.0.0"` → `.upToNextMajor(from: "1.0.0")`
  - `swift-docc-plugin`: `from: "1.4.0"` → `.upToNextMajor(from: "1.4.0")`
  - 機能的には同等だが、バージョニング戦略の意図がより明確に

## [1.1.2] - 2025-11-09

### 修正
- 自動リリースワークフローのメッセージを完全に日本語に統一（PRディスクリプション、リリースノート、ログメッセージ）

## [1.0.5] - 2025-11-04

### 追加
- DocC ドキュメントの自動生成と GitHub Pages への公開機能を追加
  - Swift DocC Plugin を依存関係に追加
  - GitHub Actions ワークフローで自動的にドキュメントを生成・デプロイ
  - README に完全なドキュメントへのリンクを追加 (https://no-problem-dev.github.io/swift-cached-remote-image/documentation/cachedremoteimage/)

### 変更
- ドキュメントへのアクセシビリティを向上

### 修正
- Swift 6 strict concurrency モードでのコンパイルエラーを修正
  - `ImageService.loadImage(from:)` に `@MainActor` を追加
  - `ImageDataCache` のメソッドに `@MainActor` を追加
  - 非 Sendable 型（`NSImage`/`UIImage`）のアクター境界問題を解決

## [1.0.4] - 2025-02-11

### 改善
- README から実装詳細を削除し、利用者視点に絞る
  - 内部動作フロー（メタデータ取得フロー）の説明を削除
  - ImageEntity 直接使用セクションを削除（実装詳細）
  - ユーザーが使う機能のみにフォーカス

## [1.0.3] - 2025-02-11

### 追加
- README に API 前提条件セクションを追加
  - `.imageId` 使用時に必要な REST API 要件を明記
  - 必須 API エンドポイントを文書化（GET, POST, DELETE）
  - 必須 JSON レスポンス形式を camelCase で明記
  - URL ベースの使用（.url/.urlString）は API サーバー不要であることを明確化

## [1.0.2] - 2025-02-11

### 改善
- README に正確な API 例とバッジを追加
  - Swift 6.0、プラットフォーム、SPM、ライセンスのバッジを追加
  - 最速のオンボーディングのためのクイックスタートセクションを追加
  - すべての例を正しい ImageSource API に修正（source: .url(), .urlString(), .imageId()）
  - ImageServiceImpl の初期化を正しいパラメータに修正
  - 包括的な ImageSource タイプの説明を追加
  - 適切なワークフローを含む ImageID 機能セクションを追加
  - 存在しない Firebase Storage セクションを削除
  - キャッシュ設定の例を追加
  - 実際の機能を反映するように機能セクションを更新

### 修正
- README の API 使用例が実装と一致しない問題を修正
- ImageServiceImpl の初期化パラメータの誤りを修正

## [1.0.1] - 2024-12-XX

### 修正
- パッケージ名が異なる依存関係に .product() を使用

## [1.0.0] - 2024-12-XX

### 追加
- 初回リリース
- SwiftUI ネイティブな API
- メモリ & ディスクキャッシュ
- 非同期画像読み込み
- 柔軟な ImageSource（URL、URL 文字列、画像 ID）
- 画像 ID サポート
- カスタマイズ可能なリトライポリシー
- プレースホルダーとエラー表示のカスタマイズ
- キャッシュ管理
- iOS 17.0+ および macOS 14.0+ サポート

[未リリース]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.5...HEAD
[1.1.5]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.0.5...v1.1.2
[1.0.5]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.0.4...v1.0.5

<!-- Auto-generated on 2025-11-09T05:06:53Z by release workflow -->

<!-- Auto-generated on 2025-11-13T01:14:35Z by release workflow -->

<!-- Auto-generated on 2026-01-08T00:03:15Z by release workflow -->
