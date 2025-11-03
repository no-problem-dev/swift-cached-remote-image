import Foundation

/// 画像リソースの最小限の情報
///
/// キャッシュ可能なリモート画像の識別とアクセスに必要な情報のみを保持します。
/// 画像の詳細なメタデータは別ドメインで管理します。
public struct ImageResource: Sendable, Identifiable, Equatable {
    /// 画像の一意識別子
    public let id: String

    /// 画像のアクセス可能なURL
    public let url: URL

    /// 画像リソースを初期化します
    /// - Parameters:
    ///   - id: 画像の一意識別子
    ///   - url: 画像のURL
    public init(id: String, url: URL) {
        self.id = id
        self.url = url
    }
}
