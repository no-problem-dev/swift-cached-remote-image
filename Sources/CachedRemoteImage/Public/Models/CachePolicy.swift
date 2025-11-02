/// キャッシュ戦略を制御する列挙型
///
/// キャッシュの動作を柔軟に制御することで、パフォーマンスとリソース使用のバランスを調整できます。
///
/// ## 使用例
/// ```swift
/// // すべてキャッシュを利用（デフォルト、推奨）
/// CachedRemoteImage(source: .imageId("abc"), cachePolicy: .all)
///
/// // メタデータのみキャッシュ（画像は毎回ダウンロード）
/// CachedRemoteImage(source: .imageId("abc"), cachePolicy: .metadataOnly)
///
/// // キャッシュを一切使わない（常に最新を取得）
/// CachedRemoteImage(source: .imageId("abc"), cachePolicy: .none)
/// ```
public enum CachePolicy: Equatable, Sendable {
    /// メタデータと画像データの両方をキャッシュ（推奨）
    ///
    /// 最も効率的で、通常はこれを使用します。
    case all

    /// メタデータのみキャッシュ、画像データは毎回ダウンロード
    ///
    /// 画像の最新性を保ちたいが、メタデータ取得のコストは削減したい場合に使用
    case metadataOnly

    /// 画像データのみキャッシュ、メタデータは毎回取得
    ///
    /// メタデータが頻繁に更新されるが、画像自体は変わらない場合に使用
    case imageOnly

    /// キャッシュを一切使用しない
    ///
    /// 常に最新のデータを取得したい場合に使用。パフォーマンスは低下します。
    case none

    /// メタデータキャッシュを使用するかどうか
    internal var shouldCacheMetadata: Bool {
        switch self {
        case .all, .metadataOnly:
            return true
        case .imageOnly, .none:
            return false
        }
    }

    /// 画像データキャッシュを使用するかどうか
    internal var shouldCacheImage: Bool {
        switch self {
        case .all, .imageOnly:
            return true
        case .metadataOnly, .none:
            return false
        }
    }
}
