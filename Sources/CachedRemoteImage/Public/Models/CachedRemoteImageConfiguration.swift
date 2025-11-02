/// CachedRemoteImageの設定
///
/// 画像読み込みの動作を細かく制御するための設定オブジェクトです。
///
/// ## 使用例
/// ```swift
/// // デフォルト設定
/// let config = CachedRemoteImageConfiguration()
///
/// // カスタム設定
/// let config = CachedRemoteImageConfiguration(
///     cachePolicy: .metadataOnly,
///     retryPolicy: .exponentialBackoff(maxRetries: 3)
/// )
/// ```
public struct CachedRemoteImageConfiguration: Equatable, Sendable {
    /// キャッシュ戦略
    public let cachePolicy: CachePolicy

    /// リトライ戦略
    public let retryPolicy: RetryPolicy

    /// デフォルト設定で初期化
    ///
    /// - Parameters:
    ///   - cachePolicy: キャッシュ戦略（デフォルト: .all）
    ///   - retryPolicy: リトライ戦略（デフォルト: .none）
    public init(
        cachePolicy: CachePolicy = .all,
        retryPolicy: RetryPolicy = .none
    ) {
        self.cachePolicy = cachePolicy
        self.retryPolicy = retryPolicy
    }

    /// すべてキャッシュする標準設定
    public static let standard = CachedRemoteImageConfiguration()

    /// キャッシュを使わない設定（常に最新を取得）
    public static let noCache = CachedRemoteImageConfiguration(cachePolicy: .none)

    /// リトライ付き設定（ネットワークが不安定な環境向け）
    public static let withRetry = CachedRemoteImageConfiguration(
        retryPolicy: .exponentialBackoff(maxRetries: 3)
    )
}
