import XCTest
@testable import CachedRemoteImage

final class RetryPolicyTests: XCTestCase {
    func testMaxRetries() {
        XCTAssertEqual(RetryPolicy.none.maxRetries, 0)
        XCTAssertEqual(RetryPolicy.fixed(count: 3).maxRetries, 3)
        XCTAssertEqual(RetryPolicy.exponentialBackoff(maxRetries: 5).maxRetries, 5)
    }

    func testMaxRetriesClampsNegativeValues() {
        XCTAssertEqual(RetryPolicy.fixed(count: -1).maxRetries, 0)
        XCTAssertEqual(RetryPolicy.exponentialBackoff(maxRetries: -2).maxRetries, 0)
    }

    func testDelayIsZeroForNoneAndFixed() {
        XCTAssertEqual(RetryPolicy.none.delay(for: 0), 0)
        XCTAssertEqual(RetryPolicy.fixed(count: 3).delay(for: 2), 0)
    }

    func testExponentialBackoffDelayDoublesPerAttempt() {
        let policy = RetryPolicy.exponentialBackoff(maxRetries: 5, baseDelay: 1.0)
        let delays = (0..<4).map { policy.delay(for: $0) }
        XCTAssertEqual(delays, [1.0, 2.0, 4.0, 8.0])
    }
}

final class ImageCacheKeyTests: XCTestCase {
    func testSameKeyResolvesToTheSameFileName() {
        XCTAssertEqual(ImageCacheKey.id("img-1").fileName, ImageCacheKey.id("img-1").fileName)
    }

    func testIdAndURLNamespacesDoNotOverlap() {
        let shared = "https://example.com/a.jpg"
        XCTAssertNotEqual(ImageCacheKey.id(shared).fileName, ImageCacheKey.url(shared).fileName)
        XCTAssertNotEqual(ImageCacheKey.id(shared).memoryKey, ImageCacheKey.url(shared).memoryKey)
    }

    func testFileNameIsFixedLengthAndPathSafe() {
        // ID や URL をそのままファイル名にすると、長さ上限と区切り文字の両方に引っかかる
        let long = String(repeating: "a", count: 5000)
        let fileName = ImageCacheKey.id(long).fileName
        XCTAssertEqual(fileName.count, 64)
        XCTAssertFalse(fileName.contains("/"))
    }
}

final class ImageCacheLocationTests: XCTestCase {
    func testDirectoryLocationIsCreatedOnResolve() throws {
        let target = makeTemporaryCacheDirectory()
        defer { try? FileManager.default.removeItem(at: target) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let resolved = try ImageCacheLocation.directory(target).resolvedDirectory()

        XCTAssertEqual(resolved, target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testUnusableLocationFailsLoudlyAtConstruction() throws {
        // 置き場所を用意できないのは設定ミス。黙って別の場所に落とすと、
        // ウィジェットが何も出せない理由が最後まで分からなくなる。
        // （App Group の entitlement 忘れは iOS でのみ nil になる挙動で、macOS では再現できない。
        //   ここでは「作れない場所は init で落ちる」という同じ保証を、作れないパスで確かめる）
        let unusable = URL(fileURLWithPath: "/dev/null/cannot-create-here")

        XCTAssertThrowsError(try ImageCacheLocation.directory(unusable).resolvedDirectory())
        XCTAssertThrowsError(
            try ImageLibrary(
                transport: FakeImageTransport(),
                configuration: ImageLibraryConfiguration(cacheLocation: .directory(unusable))
            )
        )
    }
}

final class ImageLoadErrorTests: XCTestCase {
    func testEveryCaseHasAUserFacingMessage() {
        let cases: [ImageLoadError] = [
            .libraryNotConfigured,
            .invalidURL("x"),
            .transportFailed(reason: "boom"),
            .notAnImage(byteCount: 12)
        ]
        for error in cases {
            XCTAssertFalse(error.localizedMessage.isEmpty)
        }
    }

    func testDeveloperDescriptionKeepsTheCause() {
        XCTAssertEqual(
            ImageLoadError.transportFailed(reason: "401 Unauthorized").errorDescription,
            "画像の取得に失敗: 401 Unauthorized"
        )
    }
}
