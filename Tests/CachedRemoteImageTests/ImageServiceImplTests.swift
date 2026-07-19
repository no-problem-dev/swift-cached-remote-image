import XCTest
import APIClient
@testable import CachedRemoteImage

// scoped import で DeveloperToolsSupport.ImageResource との型名衝突を回避する
import struct CachedRemoteImage.ImageResource

/// `APIExecutable` のテストダブル。実行された契約のパスを記録し、スクリプトされた結果を返す。
/// ネットワークには一切出ない。
final class MockAPIClient: APIExecutable, @unchecked Sendable {
    enum MockError: Error { case unstubbed }

    private let lock = NSLock()
    private var _executedPaths: [String] = []
    private var _resourceProvider: ((String) throws -> ImageResourceDTO)?

    /// 実行された契約の解決済みパス（実行順）。
    var executedPaths: [String] { lock.withLock { _executedPaths } }

    /// `ImageResourceDTO` を出力とする契約への応答を登録する。
    func stubResource(_ provider: @escaping (String) throws -> ImageResourceDTO) {
        lock.withLock { _resourceProvider = provider }
    }

    func executeWithResponse<E: APIContract>(_ contract: E) async throws -> APIResponse<E.Output>
        where E.Input == E, E: APIInput
    {
        let path = E.resolvePath(with: contract)
        let provider = lock.withLock { () -> ((String) throws -> ImageResourceDTO)? in
            _executedPaths.append(path)
            return _resourceProvider
        }
        if let empty = EmptyOutput() as? E.Output {
            return APIResponse(output: empty, statusCode: 200, headers: [:])
        }
        guard let provider, let output = try provider(path) as? E.Output else {
            throw MockError.unstubbed
        }
        return APIResponse(output: output, statusCode: 200, headers: [:])
    }
}

final class ImageServiceImplTests: XCTestCase {
    private func dto(_ id: String) -> ImageResourceDTO {
        ImageResourceDTO(id: id, url: "https://example.com/\(id).jpg")
    }

    private func makeService(_ client: MockAPIClient) -> ImageServiceImpl<MockAPIClient> {
        ImageServiceImpl(apiClient: client, imagesPath: "/images", maxResourceCacheSize: 10)
    }

    func testGetImageResourceFetchesOnceThenServesFromCache() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("img1") }
        let service = makeService(client)

        let first = try await service.getImageResource(imageId: "img1")
        let second = try await service.getImageResource(imageId: "img1")

        XCTAssertEqual(first, ImageResource(id: "img1", url: URL(string: "https://example.com/img1.jpg")!))
        XCTAssertEqual(second, first)
        XCTAssertEqual(client.executedPaths, ["/images/img1"], "2 回目はキャッシュが応答し API を叩かない")
    }

    func testFailedFetchIsNotCached() async throws {
        let client = MockAPIClient()
        var calls = 0
        client.stubResource { _ in
            calls += 1
            if calls == 1 { throw URLError(.timedOut) }
            return self.dto("img1")
        }
        let service = makeService(client)

        do {
            _ = try await service.getImageResource(imageId: "img1")
            XCTFail("初回はエラーになるべき")
        } catch {}

        let recovered = try await service.getImageResource(imageId: "img1")
        XCTAssertEqual(recovered.id, "img1")
        XCTAssertEqual(client.executedPaths.count, 2, "失敗はキャッシュされず再取得される")
    }

    func testUploadImagePrimesResourceCache() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("up1") }
        let service = makeService(client)

        let uploaded = try await service.uploadImage(imageData: Data("jpeg".utf8))
        let fetched = try await service.getImageResource(imageId: "up1")

        XCTAssertEqual(uploaded, fetched)
        XCTAssertEqual(client.executedPaths, ["/images"], "アップロード直後の取得はキャッシュから返る")
    }

    func testDeleteImageEvictsResourceCache() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("img1") }
        let service = makeService(client)

        _ = try await service.getImageResource(imageId: "img1")
        try await service.deleteImage(imageId: "img1")
        _ = try await service.getImageResource(imageId: "img1")

        XCTAssertEqual(
            client.executedPaths,
            ["/images/img1", "/images/img1", "/images/img1"],
            "削除後の取得はキャッシュヒットせず再フェッチされる"
        )
    }

    func testClearResourceCacheForcesRefetch() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("img1") }
        let service = makeService(client)

        _ = try await service.getImageResource(imageId: "img1")
        await service.clearResourceCache()
        _ = try await service.getImageResource(imageId: "img1")

        XCTAssertEqual(client.executedPaths.count, 2, "クリア後は API から再取得される")
    }
}
