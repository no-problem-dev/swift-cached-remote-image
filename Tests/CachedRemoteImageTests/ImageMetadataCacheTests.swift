import XCTest
@testable import CachedRemoteImage

// scoped import で DeveloperToolsSupport.ImageResource との型名衝突を回避する
import struct CachedRemoteImage.ImageResource

final class ImageMetadataCacheTests: XCTestCase {
    private func resource(_ id: String) -> ImageResource {
        ImageResource(id: id, url: URL(string: "https://example.com/\(id).jpg")!)
    }

    func testSetAndGetRoundTrip() async {
        let cache = ImageMetadataCache(maxCacheSize: 10)
        await cache.set(resource("a"), for: "a")
        let cached = await cache.get(for: "a")
        XCTAssertEqual(cached, resource("a"))
    }

    func testGetMissingReturnsNil() async {
        let cache = ImageMetadataCache(maxCacheSize: 10)
        let cached = await cache.get(for: "missing")
        XCTAssertNil(cached)
    }

    func testRemoveEvictsSingleEntry() async {
        let cache = ImageMetadataCache(maxCacheSize: 10)
        await cache.set(resource("a"), for: "a")
        await cache.set(resource("b"), for: "b")
        await cache.remove(for: "a")
        let removed = await cache.get(for: "a")
        let kept = await cache.get(for: "b")
        XCTAssertNil(removed)
        XCTAssertEqual(kept, resource("b"))
    }

    func testClearAllEvictsEverything() async {
        let cache = ImageMetadataCache(maxCacheSize: 10)
        await cache.set(resource("a"), for: "a")
        await cache.set(resource("b"), for: "b")
        await cache.clearAll()
        let a = await cache.get(for: "a")
        let b = await cache.get(for: "b")
        XCTAssertNil(a)
        XCTAssertNil(b)
    }

    func testEvictsLeastRecentlyUsedEntryWhenFull() async throws {
        let cache = ImageMetadataCache(maxCacheSize: 4)
        // 挿入順 = アクセス時刻順を保証するため、各操作の間にわずかな時間差を置く
        for id in ["a", "b", "c", "d"] {
            await cache.set(resource(id), for: id)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        // "a" にアクセスして最終アクセス時刻を更新 → 最古は "b" になる
        _ = await cache.get(for: "a")
        try await Task.sleep(nanoseconds: 5_000_000)

        // 満杯状態での set が LRU eviction をトリガーする
        await cache.set(resource("e"), for: "e")

        let evicted = await cache.get(for: "b")
        XCTAssertNil(evicted, "最も長くアクセスされていない b が追い出されるべき")
        for id in ["a", "c", "d", "e"] {
            let kept = await cache.get(for: id)
            XCTAssertEqual(kept, resource(id), "\(id) は保持されるべき")
        }
    }

    func testUpdatingExistingKeyOverwritesResource() async {
        let cache = ImageMetadataCache(maxCacheSize: 10)
        await cache.set(resource("old"), for: "key")
        await cache.set(resource("new"), for: "key")
        let cached = await cache.get(for: "key")
        XCTAssertEqual(cached, resource("new"))
    }
}
