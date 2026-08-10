import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The memory layer of the cache, holding decoded images.
///
/// Disk keeps the bytes and this keeps the decoded result, because what a scroll actually costs
/// is decoding, not reading a file. Entries do not survive the process, and the system may evict
/// them under memory pressure, so a miss here is normal rather than a failure.
///
/// Only the calls that hand an image in or out are isolated to the main actor: `PlatformImage` is
/// not `Sendable` on macOS and cannot cross isolation. `NSCache` is thread-safe by itself, so the
/// removal calls, which pass no image, need no isolation.
final class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, PlatformImage>()

    init(countLimit: Int, costLimit: Int) {
        cache.countLimit = countLimit
        cache.totalCostLimit = costLimit
    }

    @MainActor
    func image(for key: ImageCacheKey) -> PlatformImage? {
        cache.object(forKey: key.memoryKey)
    }

    @MainActor
    func store(_ image: PlatformImage, for key: ImageCacheKey) {
        cache.setObject(image, forKey: key.memoryKey, cost: memoryCost(of: image))
    }

    func remove(for key: ImageCacheKey) {
        cache.removeObject(forKey: key.memoryKey)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    /// The bytes an image occupies once decoded.
    ///
    /// Several times the compressed file size, so a cost limit only means anything if it is
    /// measured after decoding rather than from the data that arrived.
    private func memoryCost(of image: PlatformImage) -> Int {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return 0 }
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        #endif
        return cgImage.bytesPerRow * cgImage.height
    }
}
