import XCTest
@testable import CachedRemoteImage
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class ImageDataCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageDataCacheTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeCache() -> ImageDataCache {
        ImageDataCache(cacheDirectory: directory)
    }

    private func makeImage(width: Int = 8, height: Int = 8) -> PlatformImage {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
        #endif
    }

    private func diskFileCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count
    }

    // MARK: - 格納・取得

    func testSetThenGetReturnsImage() async {
        let cache = makeCache()
        let url = "https://example.com/a.jpg"
        await cache.set(makeImage(), for: url)
        let cached = await cache.get(for: url)
        XCTAssertNotNil(cached)
    }

    func testGetMissingReturnsNil() async {
        let cache = makeCache()
        let cached = await cache.get(for: "https://example.com/missing.jpg")
        XCTAssertNil(cached)
    }

    func testSetPersistsToDisk() async throws {
        let cache = makeCache()
        await cache.set(makeImage(), for: "https://example.com/a.jpg")
        XCTAssertEqual(try diskFileCount(), 1)
    }

    func testDiskLayerServesNewInstanceWithoutMemoryCache() async {
        // 1 つ目のインスタンスで書き込み → メモリキャッシュを共有しない新インスタンスで取得
        // = ディスク層単体からの復元を検証する
        let writer = makeCache()
        let url = "https://example.com/a.jpg"
        await writer.set(makeImage(width: 16, height: 16), for: url)

        let reader = makeCache()
        let restored = await reader.get(for: url)
        XCTAssertNotNil(restored, "ディスクキャッシュから復元されるべき")
    }

    func testDifferentURLsAreCachedIndependently() async throws {
        let cache = makeCache()
        await cache.set(makeImage(), for: "https://example.com/a.jpg")
        await cache.set(makeImage(), for: "https://example.com/b.jpg")
        XCTAssertEqual(try diskFileCount(), 2)
        let a = await cache.get(for: "https://example.com/a.jpg")
        let b = await cache.get(for: "https://example.com/b.jpg")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
    }

    // MARK: - 失効

    func testRemoveEvictsMemoryAndDisk() async throws {
        let cache = makeCache()
        let url = "https://example.com/a.jpg"
        await cache.set(makeImage(), for: url)
        await cache.remove(for: url)

        let cached = await cache.get(for: url)
        XCTAssertNil(cached, "メモリキャッシュから消えるべき")
        XCTAssertEqual(try diskFileCount(), 0, "ディスクからも消えるべき")
    }

    func testClearAllEvictsEverything() async throws {
        let cache = makeCache()
        await cache.set(makeImage(), for: "https://example.com/a.jpg")
        await cache.set(makeImage(), for: "https://example.com/b.jpg")
        await cache.clearAll()

        let a = await cache.get(for: "https://example.com/a.jpg")
        let b = await cache.get(for: "https://example.com/b.jpg")
        XCTAssertNil(a)
        XCTAssertNil(b)
        XCTAssertEqual(try diskFileCount(), 0)
    }

    // MARK: - diskCacheSize

    func testDiskCacheSizeIsZeroWhenEmpty() async {
        let cache = makeCache()
        let size = await cache.diskCacheSize()
        XCTAssertEqual(size, 0)
    }

    func testDiskCacheSizeSumsAllFiles() async throws {
        let cache = makeCache()
        await cache.set(makeImage(), for: "https://example.com/a.jpg")
        await cache.set(makeImage(width: 32, height: 32), for: "https://example.com/b.jpg")

        let reported = await cache.diskCacheSize()
        let expected = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .compactMap { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
            .reduce(Int64(0)) { $0 + Int64($1) }
        XCTAssertGreaterThan(reported, 0)
        XCTAssertEqual(reported, expected)
    }

    func testDiskCacheSizeReturnsToZeroAfterClearAll() async {
        let cache = makeCache()
        await cache.set(makeImage(), for: "https://example.com/a.jpg")
        await cache.clearAll()
        let size = await cache.diskCacheSize()
        XCTAssertEqual(size, 0)
    }
}
