import Foundation

/// 画像の取得元を表す型安全な列挙型
///
/// ## 使用例
/// ```swift
/// // 画像IDから取得
/// CachedRemoteImage(source: .imageId("abc123"))
///
/// // URLから直接取得
/// CachedRemoteImage(source: .url(imageURL))
///
/// // URL文字列から取得
/// CachedRemoteImage(source: .urlString("https://example.com/image.jpg"))
/// ```
public enum ImageSource: Equatable, Sendable {
    /// 画像IDから取得（メタデータ取得 → 画像ダウンロードの2段階）
    case imageId(String)

    /// URLオブジェクトから直接取得
    case url(URL)

    /// URL文字列から取得（自動的にURLに変換）
    case urlString(String)

    /// URL文字列から取得可能な場合、URLを返す
    internal var resolvedURL: URL? {
        switch self {
        case .imageId:
            return nil
        case .url(let url):
            return url
        case .urlString(let string):
            return URL(string: string)
        }
    }

    /// 画像IDの場合、その値を返す
    internal var imageId: String? {
        if case .imageId(let id) = self {
            return id
        }
        return nil
    }
}
