import Foundation

/// Cache placement, size limits and retry policy, fixed once when the library is built.
///
/// These settings belong to the library rather than to a view. The caches are a single shared
/// resource that a view does not own, and per-view settings would leave fetches that never go
/// through a view — prefetching, for instance — running under different rules from the ones on
/// screen.
public struct ImageLibraryConfiguration: Sendable {
    /// Where the disk cache directory is placed.
    ///
    /// A widget only reaches these files if it resolves its own cache from the same value.
    public let cacheLocation: ImageCacheLocation

    /// The maximum bytes to keep on disk before the oldest entries are deleted.
    ///
    /// The system never reclaims an App Group container, so when the cache lives there this
    /// ceiling is the only thing bounding how far it grows.
    public let diskCacheSizeLimit: Int64

    /// The maximum number of decoded images to hold in memory.
    ///
    /// A ceiling rather than a reservation: entries can be evicted sooner when the system is
    /// short on memory.
    public let memoryCountLimit: Int

    /// The maximum total bytes of decoded images to hold in memory.
    ///
    /// Measured after decoding, which is a different order of magnitude from the compressed file
    /// size — a few hundred kilobytes of JPEG can occupy several megabytes once decoded.
    public let memoryCostLimit: Int

    /// How failed fetches are retried; the default retries nothing.
    ///
    /// Only fetches are retried. Bytes that arrive but fail to decode are not, since decoding
    /// them again gives the same answer.
    public let retryPolicy: RetryPolicy

    /// The session used to download sources that are already URLs.
    ///
    /// Image ids never reach it: those go through ``ImageTransport``, which uses whatever
    /// authenticated client your app already has.
    public let urlSession: URLSession

    /// - Parameters:
    ///   - cacheLocation: Where the disk cache is placed. Defaults to the Caches directory.
    ///   - diskCacheSizeLimit: Bytes to keep on disk. Defaults to 100 MB.
    ///   - memoryCountLimit: Decoded images to hold in memory. Defaults to 100.
    ///   - memoryCostLimit: Bytes of decoded images to hold in memory. Defaults to 50 MB.
    ///   - retryPolicy: How failed fetches are retried. Defaults to not retrying.
    ///   - urlSession: The session used for URL sources. Defaults to `.shared`.
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

    /// The defaults: the Caches directory, 100 MB on disk, and no retries.
    public static let standard = ImageLibraryConfiguration()

    /// The defaults with exponential backoff, up to three retries.
    ///
    /// For unreliable networks. The waits are one, two and four seconds.
    public static let withRetry = ImageLibraryConfiguration(
        retryPolicy: .exponentialBackoff(maxRetries: 3)
    )

    /// Settings that put the disk cache in an App Group container, where a widget can read it.
    ///
    /// Build ``ImageDiskCache`` with the same identifier on the widget side and the same files
    /// are there. Everything else keeps its default.
    ///
    /// - Parameters:
    ///   - identifier: The App Group identifier.
    ///   - subdirectory: The directory name to use inside the container.
    public static func appGroup(
        _ identifier: String,
        subdirectory: String = "CachedRemoteImage"
    ) -> ImageLibraryConfiguration {
        ImageLibraryConfiguration(cacheLocation: .appGroup(identifier, subdirectory: subdirectory))
    }
}
