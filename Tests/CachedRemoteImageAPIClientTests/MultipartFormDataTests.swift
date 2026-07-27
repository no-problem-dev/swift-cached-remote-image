import APIClient
import XCTest
@testable import CachedRemoteImageAPIClient

final class MultipartFormDataTests: XCTestCase {
    private let payload = Data([0xFF, 0xD8, 0xFF, 0x00, 0x0A, 0x0D])

    private func string(of data: Data) -> String {
        // バイナリを含むので、判定に使う部分だけが読めれば足りる
        String(decoding: data, as: UTF8.self)
    }

    func testBoundaryInHeaderMatchesTheBodyDelimiter() {
        let form = MultipartFormData(boundary: "TEST-BOUNDARY")
        let body = form.body(fieldName: "file", fileName: "image.png", contentType: "image/png", data: payload)

        XCTAssertEqual(form.contentTypeHeaderValue, "multipart/form-data; boundary=TEST-BOUNDARY")
        XCTAssertTrue(string(of: body).hasPrefix("--TEST-BOUNDARY\r\n"))
        XCTAssertTrue(string(of: body).hasSuffix("\r\n--TEST-BOUNDARY--\r\n"), "終端の区切りが無いとサーバーは本文を読み切れない")
    }

    func testPartCarriesFieldNameFileNameAndContentType() {
        let body = MultipartFormData(boundary: "B").body(
            fieldName: "image",
            fileName: "image.jpg",
            contentType: "image/jpeg",
            data: payload
        )

        let text = string(of: body)
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\""))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
    }

    func testPayloadIsCarriedVerbatim() {
        let body = MultipartFormData(boundary: "B").body(
            fieldName: "file",
            fileName: "image.png",
            contentType: "image/png",
            data: payload
        )

        XCTAssertNotNil(body.range(of: payload), "バイト列は加工せずそのまま載せる（Base64 で 33% 膨らませない）")
    }

    func testEachInstanceGetsItsOwnBoundary() {
        XCTAssertNotEqual(MultipartFormData().boundary, MultipartFormData().boundary)
    }

    func testFileNameFollowsTheContentType() {
        XCTAssertEqual(MultipartFormData.fileName(for: "image/jpeg"), "image.jpg")
        XCTAssertEqual(MultipartFormData.fileName(for: "image/png"), "image.png")
        XCTAssertEqual(MultipartFormData.fileName(for: "image/heic"), "image.heic")
    }

    func testUploadContractBuildsAMatchingHeaderAndBody() throws {
        let contract = UploadImageContract(
            basePath: "/images",
            imageData: payload,
            contentType: "image/png",
            fieldName: "file",
            boundary: "FIXED"
        )

        let body = try XCTUnwrap(contract.encodeBody(using: JSONEncoder()))

        XCTAssertEqual(contract.additionalHeaders["Content-Type"], "multipart/form-data; boundary=FIXED")
        XCTAssertTrue(string(of: body).hasPrefix("--FIXED\r\n"))
    }
}

final class ImageURLCacheTests: XCTestCase {
    private func url(_ id: String) -> URL {
        URL(string: "https://example.com/\(id).jpg")!
    }

    func testSetAndGetRoundTrip() async {
        let cache = ImageURLCache(maxCacheSize: 10)
        await cache.set(url("a"), for: "a")
        let cached = await cache.url(for: "a")
        XCTAssertEqual(cached, url("a"))
    }

    func testGetMissingReturnsNil() async {
        let cache = ImageURLCache(maxCacheSize: 10)
        let cached = await cache.url(for: "missing")
        XCTAssertNil(cached)
    }

    func testRemoveEvictsSingleEntry() async {
        let cache = ImageURLCache(maxCacheSize: 10)
        await cache.set(url("a"), for: "a")
        await cache.set(url("b"), for: "b")
        await cache.remove(for: "a")

        let removed = await cache.url(for: "a")
        let kept = await cache.url(for: "b")
        XCTAssertNil(removed)
        XCTAssertEqual(kept, url("b"))
    }

    func testRemoveAllEvictsEverything() async {
        let cache = ImageURLCache(maxCacheSize: 10)
        await cache.set(url("a"), for: "a")
        await cache.set(url("b"), for: "b")
        await cache.removeAll()

        let a = await cache.url(for: "a")
        let b = await cache.url(for: "b")
        XCTAssertNil(a)
        XCTAssertNil(b)
    }

    func testEvictsLeastRecentlyUsedEntryWhenFull() async throws {
        let cache = ImageURLCache(maxCacheSize: 4)
        // 挿入順 = アクセス時刻順を保証するため、各操作の間にわずかな時間差を置く
        for id in ["a", "b", "c", "d"] {
            await cache.set(url(id), for: id)
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        // "a" にアクセスして最終アクセス時刻を更新 → 最古は "b" になる
        _ = await cache.url(for: "a")
        try await Task.sleep(nanoseconds: 5_000_000)

        await cache.set(url("e"), for: "e")

        let evicted = await cache.url(for: "b")
        XCTAssertNil(evicted, "最も長くアクセスされていない b が追い出されるべき")
        for id in ["a", "c", "d", "e"] {
            let kept = await cache.url(for: id)
            XCTAssertEqual(kept, url(id), "\(id) は保持されるべき")
        }
    }

    func testUpdatingExistingKeyOverwritesTheURL() async {
        let cache = ImageURLCache(maxCacheSize: 10)
        await cache.set(url("old"), for: "key")
        await cache.set(url("new"), for: "key")
        let cached = await cache.url(for: "key")
        XCTAssertEqual(cached, url("new"))
    }
}
