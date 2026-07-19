import XCTest
@testable import CachedRemoteImage

// scoped import で DeveloperToolsSupport.ImageResource との型名衝突を回避する
import struct CachedRemoteImage.ImageResource

final class CachePolicyTests: XCTestCase {
    func testShouldCacheMetadata() {
        XCTAssertTrue(CachePolicy.all.shouldCacheMetadata)
        XCTAssertTrue(CachePolicy.metadataOnly.shouldCacheMetadata)
        XCTAssertFalse(CachePolicy.imageOnly.shouldCacheMetadata)
        XCTAssertFalse(CachePolicy.none.shouldCacheMetadata)
    }

    func testShouldCacheImage() {
        XCTAssertTrue(CachePolicy.all.shouldCacheImage)
        XCTAssertFalse(CachePolicy.metadataOnly.shouldCacheImage)
        XCTAssertTrue(CachePolicy.imageOnly.shouldCacheImage)
        XCTAssertFalse(CachePolicy.none.shouldCacheImage)
    }
}

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

    func testDelayIsZeroForNoneAndFixed() async {
        let none = await RetryPolicy.none.delay(for: 0)
        XCTAssertEqual(none, 0)
        let fixed = await RetryPolicy.fixed(count: 3).delay(for: 2)
        XCTAssertEqual(fixed, 0)
    }

    func testExponentialBackoffDelayDoublesPerAttempt() async {
        let policy = RetryPolicy.exponentialBackoff(maxRetries: 5, baseDelay: 1.0)
        var delays: [TimeInterval] = []
        for attempt in 0..<4 {
            delays.append(await policy.delay(for: attempt))
        }
        XCTAssertEqual(delays, [1.0, 2.0, 4.0, 8.0])
    }
}

final class ImageResourceTests: XCTestCase {
    func testIdentityAndEquality() {
        let url = URL(string: "https://example.com/image.jpg")!
        let a = ImageResource(id: "img1", url: url)
        let b = ImageResource(id: "img1", url: url)
        let c = ImageResource(id: "img2", url: url)
        XCTAssertEqual(a.id, "img1")
        XCTAssertEqual(a.url, url)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
