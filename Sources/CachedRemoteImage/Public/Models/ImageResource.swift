import Foundation

/// 画像リソースの最小限の情報
///
/// キャッシュ可能なリモート画像の識別とアクセスに必要な情報のみを保持する。
/// 画像の詳細なメタデータは別ドメインで管理する。
public struct ImageResource: Sendable, Identifiable, Equatable {
    /// 画像の一意識別子
    public let id: String

    /// 画像のアクセス可能なURL
    public let url: URL

    /// IDとURLから画像リソースを生成する。
    ///
    /// - Parameters:
    ///   - id: 画像の一意識別子
    ///   - url: 画像の公開 URL
    public init(id: String, url: URL) {
        self.id = id
        self.url = url
    }
}
