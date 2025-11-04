import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// 画像データのキャッシュ（NSCache + Disk storage）
///
/// URL → UIImage のマッピングを管理
/// - メモリキャッシュ: NSCache（50MB制限、100画像まで）
/// - ディスクキャッシュ: ファイルシステム（永続化）
internal final class ImageDataCache: @unchecked Sendable {
    #if canImport(UIKit)
    private let memoryCache = NSCache<NSString, UIImage>()
    #elseif canImport(AppKit)
    private let memoryCache = NSCache<NSString, NSImage>()
    #endif
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    init() {
        // キャッシュディレクトリの設定
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("CachedRemoteImage")

        // ディレクトリ作成
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }

        // メモリキャッシュの設定
        memoryCache.countLimit = 100 // 最大100画像
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    /// キャッシュされた画像を取得
    @MainActor
    func get(for url: String) async -> PlatformImage? {
        let key = cacheKey(for: url)

        // メモリキャッシュを確認
        if let image = memoryCache.object(forKey: key as NSString) {
            return image
        }

        // ディスクキャッシュを確認
        let fileURL = diskCacheURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let image = PlatformImage(data: data) else {
            return nil
        }

        // メモリキャッシュに復元（次回高速化）
        let cost = imageMemoryCost(image)
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)

        return image
    }

    /// 画像をキャッシュに保存
    @MainActor
    func set(_ image: PlatformImage, for url: String) async {
        let key = cacheKey(for: url)

        // メモリキャッシュに保存
        let cost = imageMemoryCost(image)
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)

        // ディスクキャッシュに保存
        let fileURL = diskCacheURL(for: key)
        #if canImport(UIKit)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
        #elseif canImport(AppKit)
        if let tiffData = image.tiffRepresentation,
           let bitmapImage = NSBitmapImageRep(data: tiffData),
           let data = bitmapImage.representation(using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.8]) {
            try? data.write(to: fileURL)
        }
        #endif
    }

    /// 特定の画像を削除
    func remove(for url: String) async {
        let key = cacheKey(for: url)

        // メモリキャッシュから削除
        memoryCache.removeObject(forKey: key as NSString)

        // ディスクキャッシュから削除
        let fileURL = diskCacheURL(for: key)
        try? fileManager.removeItem(at: fileURL)
    }

    /// すべてのキャッシュをクリア
    func clearAll() async {
        // メモリキャッシュをクリア
        memoryCache.removeAllObjects()

        // ディスクキャッシュをクリア
        if let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for fileURL in contents {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    /// キャッシュサイズを取得（ディスクのみ）
    func getCacheSize() async -> Int64 {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }

        var totalSize: Int64 = 0
        for fileURL in contents {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }

        return totalSize
    }

    // MARK: - Private Methods

    /// URLからキャッシュキーを生成
    private func cacheKey(for url: String) -> String {
        return url.data(using: .utf8)?.base64EncodedString() ?? url
    }

    /// キャッシュキーからディスクURL取得
    private func diskCacheURL(for key: String) -> URL {
        let filename = key.replacingOccurrences(of: "/", with: "_")
        return cacheDirectory.appendingPathComponent(filename)
    }

    /// 画像のメモリコストを計算
    private func imageMemoryCost(_ image: PlatformImage) -> Int {
        #if canImport(UIKit)
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
        #elseif canImport(AppKit)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
        #endif
    }
}
