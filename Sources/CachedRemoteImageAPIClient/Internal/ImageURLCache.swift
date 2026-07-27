import Foundation

/// 画像 ID → 公開 URL のキャッシュ（LRU）。
///
/// バイト列そのもののキャッシュは ``ImageLibrary`` 側にある。ここが持つのは
/// 「ID から URL を引く」1 往復ぶんだけ — この経路にしか存在しない中間段だから。
actor ImageURLCache {
    private var entries: [String: Entry] = [:]
    private let maxCacheSize: Int

    private struct Entry {
        let url: URL
        var lastAccessTime: Date
    }

    init(maxCacheSize: Int = 100) {
        self.maxCacheSize = maxCacheSize
    }

    func url(for imageId: String) -> URL? {
        guard var entry = entries[imageId] else { return nil }
        entry.lastAccessTime = Date()
        entries[imageId] = entry
        return entry.url
    }

    func set(_ url: URL, for imageId: String) {
        if entries.count >= maxCacheSize {
            evictOldestEntries()
        }
        entries[imageId] = Entry(url: url, lastAccessTime: Date())
    }

    func remove(for imageId: String) {
        entries.removeValue(forKey: imageId)
    }

    func removeAll() {
        entries.removeAll()
    }

    /// 満杯になったら 1 件ずつではなくまとめて捨てる。
    /// 上限付近で毎回 1 件だけ捨てると、その後の追加のたびに全体を並べ替えることになる
    private func evictOldestEntries() {
        let entriesToRemove = max(1, maxCacheSize / 10)
        let sorted = entries.sorted { $0.value.lastAccessTime < $1.value.lastAccessTime }
        for entry in sorted.prefix(entriesToRemove) {
            entries.removeValue(forKey: entry.key)
        }
    }
}
