import XCTest
@testable import CachedRemoteImage

/// ディスク層の性質。ここが崩れるとウィジェットが画像を出せなくなる
final class ImageDiskCacheTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = makeTemporaryCacheDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeCache(sizeLimit: Int64 = 100 * 1024 * 1024) throws -> ImageDiskCache {
        try ImageDiskCache(location: .directory(directory), sizeLimit: sizeLimit)
    }

    // MARK: - 格納・取得

    func testStoredBytesComeBackByteForByte() throws {
        let cache = try makeCache()
        let original = TestImage.pngData(width: 16, height: 16)

        cache.store(original, for: .id("img-1"))

        XCTAssertEqual(
            cache.imageData(for: "img-1"),
            original,
            "受け取ったバイト列をそのまま返すべき（復号→再エンコードで別物にしない）"
        )
    }

    func testMissingIdReturnsNil() throws {
        let cache = try makeCache()
        XCTAssertNil(cache.imageData(for: "unknown"))
    }

    func testContainsSeesStoredEntryWithoutReading() throws {
        let cache = try makeCache()
        XCTAssertFalse(cache.contains("img-1"))
        cache.store(TestImage.pngData(), for: .id("img-1"))
        XCTAssertTrue(cache.contains("img-1"))
    }

    func testNewInstanceReadsWhatAnotherInstanceWrote() throws {
        let writer = try makeCache()
        let bytes = TestImage.pngData(width: 8, height: 8)
        writer.store(bytes, for: .id("img-1"))

        // ウィジェット拡張は別プロセスで別インスタンスを作る。同じ場所を指していれば読めるべき
        let reader = try makeCache()
        XCTAssertEqual(reader.imageData(for: "img-1"), bytes)
    }

    // MARK: - キーの名前空間

    func testIdAndURLKeysDoNotCollide() throws {
        let cache = try makeCache()
        let asId = Data("stored-as-id".utf8)
        let asURL = Data("stored-as-url".utf8)
        let sameString = "https://example.com/a.jpg"

        cache.store(asId, for: .id(sameString))
        cache.store(asURL, for: .url(sameString))

        XCTAssertEqual(cache.data(for: .id(sameString)), asId)
        XCTAssertEqual(cache.data(for: .url(sameString)), asURL, "ID と URL が同じ文字列でも別の画像として扱うべき")
    }

    func testDifferentIdsAreStoredIndependently() throws {
        let cache = try makeCache()
        cache.store(Data("a".utf8), for: .id("a"))
        cache.store(Data("b".utf8), for: .id("b"))

        XCTAssertEqual(cache.imageData(for: "a"), Data("a".utf8))
        XCTAssertEqual(cache.imageData(for: "b"), Data("b".utf8))
    }

    // MARK: - 失効

    func testRemoveEvictsSingleEntry() throws {
        let cache = try makeCache()
        cache.store(Data("a".utf8), for: .id("a"))
        cache.store(Data("b".utf8), for: .id("b"))

        cache.remove(for: .id("a"))

        XCTAssertNil(cache.imageData(for: "a"))
        XCTAssertEqual(cache.imageData(for: "b"), Data("b".utf8))
    }

    func testRemoveAllEvictsEverything() throws {
        let cache = try makeCache()
        cache.store(Data("a".utf8), for: .id("a"))
        cache.store(Data("b".utf8), for: .id("b"))

        cache.removeAll()

        XCTAssertNil(cache.imageData(for: "a"))
        XCTAssertNil(cache.imageData(for: "b"))
        XCTAssertEqual(cache.totalBytes(), 0)
    }

    // MARK: - サイズ

    func testTotalBytesSumsStoredEntries() throws {
        let cache = try makeCache()
        cache.store(Data(repeating: 0, count: 300), for: .id("a"))
        cache.store(Data(repeating: 0, count: 700), for: .id("b"))

        XCTAssertEqual(cache.totalBytes(), 1000)
    }

    func testTotalBytesIsZeroWhenEmpty() throws {
        let cache = try makeCache()
        XCTAssertEqual(cache.totalBytes(), 0)
    }

    // MARK: - 上限

    func testWritingPastTheSizeLimitEvictsOldestFirst() throws {
        // App Group に置くと OS は消してくれない。上限を持たないと端末の空きが戻らない
        let cache = try makeCache(sizeLimit: 1000)

        cache.store(Data(repeating: 1, count: 400), for: .id("oldest"))
        try waitForDistinctModificationDate()
        cache.store(Data(repeating: 2, count: 400), for: .id("middle"))
        try waitForDistinctModificationDate()
        cache.store(Data(repeating: 3, count: 400), for: .id("newest"))

        XCTAssertNil(cache.imageData(for: "oldest"), "上限を超えたら古い順に消えるべき")
        XCTAssertNotNil(cache.imageData(for: "middle"))
        XCTAssertNotNil(cache.imageData(for: "newest"))
        XCTAssertLessThanOrEqual(cache.totalBytes(), 1000)
    }

    func testStayingUnderTheLimitKeepsEverything() throws {
        let cache = try makeCache(sizeLimit: 1000)
        cache.store(Data(repeating: 1, count: 400), for: .id("a"))
        cache.store(Data(repeating: 2, count: 400), for: .id("b"))

        XCTAssertNotNil(cache.imageData(for: "a"))
        XCTAssertNotNil(cache.imageData(for: "b"))
    }

    /// ファイルの更新時刻の分解能より短い間隔で書くと、古い順が決まらない
    private func waitForDistinctModificationDate() throws {
        Thread.sleep(forTimeInterval: 0.02)
    }
}
