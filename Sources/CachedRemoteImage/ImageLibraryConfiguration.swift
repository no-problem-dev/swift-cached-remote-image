import Foundation

/// ``ImageLibrary`` の設定。
///
/// 3.x では設定を「ビューごと」に渡していたが、キャッシュもリトライもライブラリが一つ持つ資源で、
/// ビューごとに変えられる性質のものではなかった（実際 `cachePolicy` はどこからも読まれておらず、
/// 渡しても何も起きなかった）。4.0 では設定はライブラリを作るときに一度だけ渡す。
/// こうするとビューを経由しない呼び出し（``ImageLibrary/prefetch(_:)`` など）にも同じ設定が効く。
public struct ImageLibraryConfiguration: Sendable {
    /// ディスクキャッシュの置き場所
    public let cacheLocation: ImageCacheLocation

    /// ディスクキャッシュの上限（バイト）。超えたぶんは古い順に消える
    public let diskCacheSizeLimit: Int64

    /// メモリに載せる復号済み画像の最大枚数
    public let memoryCountLimit: Int

    /// メモリに載せる復号済み画像の合計上限（バイト）
    public let memoryCostLimit: Int

    /// 取得失敗時の再試行。既定は再試行しない
    public let retryPolicy: RetryPolicy

    /// URL 直接指定（``ImageSource/url(_:)`` / ``ImageSource/urlString(_:)``）のダウンロードに使うセッション。
    ///
    /// 画像 ID 経路はここを通らない（``ImageTransport`` がアプリ側の認証つきクライアントを使う）。
    public let urlSession: URLSession

    /// - Parameters:
    ///   - cacheLocation: ディスクキャッシュの置き場所（既定: Caches 配下）
    ///   - diskCacheSizeLimit: ディスク上限（既定: 100MB）
    ///   - memoryCountLimit: メモリ上の最大枚数（既定: 100）
    ///   - memoryCostLimit: メモリ上の合計上限（既定: 50MB）
    ///   - retryPolicy: 再試行（既定: しない）
    ///   - urlSession: URL 直接指定に使うセッション（既定: `.shared`）
    public init(
        cacheLocation: ImageCacheLocation = .caches,
        diskCacheSizeLimit: Int64 = 100 * 1024 * 1024,
        memoryCountLimit: Int = 100,
        memoryCostLimit: Int = 50 * 1024 * 1024,
        retryPolicy: RetryPolicy = .none,
        urlSession: URLSession = .shared
    ) {
        self.cacheLocation = cacheLocation
        self.diskCacheSizeLimit = diskCacheSizeLimit
        self.memoryCountLimit = memoryCountLimit
        self.memoryCostLimit = memoryCostLimit
        self.retryPolicy = retryPolicy
        self.urlSession = urlSession
    }

    /// 既定設定（Caches 配下・再試行なし）
    public static let standard = ImageLibraryConfiguration()

    /// ネットワークが不安定な環境向け（指数バックオフで 3 回まで再試行）
    public static let withRetry = ImageLibraryConfiguration(
        retryPolicy: .exponentialBackoff(maxRetries: 3)
    )

    /// ウィジェットと画像を共有する構成。
    ///
    /// ウィジェット側は同じ識別子で ``ImageDiskCache`` を作れば、そのまま同じ画像が読める。
    ///
    /// - Parameters:
    ///   - identifier: App Group 識別子
    ///   - subdirectory: コンテナ内のサブディレクトリ名
    public static func appGroup(
        _ identifier: String,
        subdirectory: String = "CachedRemoteImage"
    ) -> ImageLibraryConfiguration {
        ImageLibraryConfiguration(cacheLocation: .appGroup(identifier, subdirectory: subdirectory))
    }
}
