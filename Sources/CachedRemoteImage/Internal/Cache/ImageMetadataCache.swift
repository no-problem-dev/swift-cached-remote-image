import Foundation
import GeneralDomain

/// 画像メタデータのキャッシュ（Actor-based with LRU eviction）
///
/// imageId → ImageEntity のマッピングをメモリ上で管理
/// LRU（Least Recently Used）アルゴリズムで古いエントリを自動削除
internal actor ImageMetadataCache {
    private var cache: [String: CacheEntry] = [:]
    private let maxCacheSize: Int

    private struct CacheEntry {
        let metadata: ImageEntity
        var lastAccessTime: Date
    }

    init(maxCacheSize: Int = 100) {
        self.maxCacheSize = maxCacheSize
    }

    /// キャッシュされたメタデータを取得
    func get(for imageId: String) -> ImageEntity? {
        guard var entry = cache[imageId] else {
            return nil
        }

        // LRU: アクセス時刻を更新
        entry.lastAccessTime = Date()
        cache[imageId] = entry

        return entry.metadata
    }

    /// メタデータをキャッシュに保存
    func set(_ entity: ImageEntity, for imageId: String) {
        // キャッシュが満杯の場合、古いエントリを削除
        if cache.count >= maxCacheSize {
            evictOldestEntries()
        }

        let entry = CacheEntry(
            metadata: entity,
            lastAccessTime: Date()
        )
        cache[imageId] = entry
    }

    /// 特定のメタデータを削除
    func remove(for imageId: String) {
        cache.removeValue(forKey: imageId)
    }

    /// すべてのキャッシュをクリア
    func clearAll() {
        cache.removeAll()
    }

    // MARK: - Private Methods

    /// 最も古いエントリを削除（LRU）
    private func evictOldestEntries() {
        let entriesToRemove = max(1, maxCacheSize / 10) // 10%削除
        let sortedEntries = cache.sorted { $0.value.lastAccessTime < $1.value.lastAccessTime }

        for entry in sortedEntries.prefix(entriesToRemove) {
            cache.removeValue(forKey: entry.key)
        }
    }
}
