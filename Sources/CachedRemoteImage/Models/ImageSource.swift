import Foundation

/// 画像の取得元を表す型安全な列挙型
///
/// ## 使用例
/// ```swift
/// // 画像IDから取得（ImageTransport 経由）
/// CachedRemoteImage(source: .imageId("abc123"))
///
/// // URLから直接取得（認証の要らない外部画像）
/// CachedRemoteImage(source: .url(imageURL))
///
/// // URL文字列から取得
/// CachedRemoteImage(source: .urlString("https://example.com/image.jpg"))
/// ```
public enum ImageSource: Equatable, Sendable, Hashable {
    /// 画像 ID から取得する。アプリが与えた ``ImageTransport`` を通る
    case imageId(String)

    /// URL から直接取得する。``ImageTransport`` は通らない
    case url(URL)

    /// URL 文字列から取得する。URL にできない文字列は
    /// ``ImageLoadError/invalidURL(_:)`` になる
    case urlString(String)
}
