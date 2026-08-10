import CryptoKit
import Foundation

/// A cache key that keeps image ids and URLs in separate name spaces.
///
/// Both kinds share one directory and one `NSCache`, so without a prefix an id that happens to
/// read like a URL could land on an entry stored for a real one. A collision here serves the
/// wrong image, which is the worst way a cache can break, so the two are separated by type.
enum ImageCacheKey: Hashable, Sendable {
    case id(String)
    case url(String)

    /// The key as a string, prefixed with which of the two kinds it is.
    private var namespaced: String {
        switch self {
        case .id(let id): return "id:\(id)"
        case .url(let url): return "url:\(url)"
        }
    }

    /// The name-spaced key as an `NSString`, which is the key type `NSCache` requires.
    var memoryKey: NSString {
        namespaced as NSString
    }

    /// The file name on disk: a SHA-256 digest of the name-spaced key.
    ///
    /// Ids and URLs cannot be file names as they stand — they run into both the 255-byte length
    /// limit and the path separator. Hashing the key rather than the bytes it points at gives a
    /// fixed-length, safe name whatever shape the key has.
    var fileName: String {
        let digest = SHA256.hash(data: Data(namespaced.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
