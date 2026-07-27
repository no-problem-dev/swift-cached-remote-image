import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 復号済み画像のメモリキャッシュ。
///
/// ディスクにはバイト列、メモリには復号済みの画像を置く。
/// スクロール中に効くのは復号のスキップで、ファイル読み込みのスキップではないため。
///
/// 画像を出し入れする口だけ `@MainActor` にしてある。`PlatformImage` は
/// macOS では非 Sendable で、隔離をまたいで渡せない。NSCache 自体はスレッドセーフなので、
/// 何も手渡さない削除系は隔離を要求しない。
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

    /// 復号後にメモリを占める実バイト数。圧縮後のファイルサイズとは桁が違うので、
    /// 上限を意味のあるものにするには復号後で測る必要がある
    private func memoryCost(of image: PlatformImage) -> Int {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return 0 }
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        #endif
        return cgImage.bytesPerRow * cgImage.height
    }
}
