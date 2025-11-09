# Changelog

このプロジェクトのすべての重要な変更は、このファイルに記録されます。

このフォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に基づいており、
このプロジェクトは [Semantic Versioning](https://semver.org/lang/ja/) に準拠しています。

## [未リリース]

なし


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

[未リリース]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.1...HEAD
