import APIClient
import XCTest
@testable import CachedRemoteImageAPIClient

/// 従来型（メタデータ API で URL を引いてから取る）バックエンド向けの transport
final class URLImageTransportTests: XCTestCase {
    private let imageBytes = Data("pretend-these-are-image-bytes".utf8)

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func dto(_ id: String) -> ImageResourceDTO {
        ImageResourceDTO(id: id, url: "https://example.com/\(id).jpg")
    }

    private func makeTransport(_ client: MockAPIClient) -> URLImageTransport<MockAPIClient> {
        URLImageTransport(
            apiClient: client,
            imagesPath: "/images",
            maxURLCacheSize: 10,
            urlSession: StubURLProtocol.makeSession()
        )
    }

    // MARK: - 取得

    func testFetchResolvesTheURLThenDownloadsTheBytes() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("img1") }
        StubURLProtocol.stub("https://example.com/img1.jpg", data: imageBytes)

        let data = try await makeTransport(client).fetch(id: "img1")

        XCTAssertEqual(data, imageBytes)
        XCTAssertEqual(client.executedPaths, ["/images/img1"])
        XCTAssertEqual(StubURLProtocol.requestedURLs, ["https://example.com/img1.jpg"])
    }

    func testURLLookupIsCachedAcrossFetches() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("img1") }
        StubURLProtocol.stub("https://example.com/img1.jpg", data: imageBytes)
        let transport = makeTransport(client)

        _ = try await transport.fetch(id: "img1")
        _ = try await transport.fetch(id: "img1")

        XCTAssertEqual(client.executedPaths, ["/images/img1"], "2 回目はメタデータ API を叩かない")
        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 2, "バイト列のキャッシュは ImageLibrary 側の担当")
    }

    func testFailedLookupIsNotCached() async throws {
        let client = MockAPIClient()
        var calls = 0
        client.stubResource { _ in
            calls += 1
            if calls == 1 { throw URLError(.timedOut) }
            return self.dto("img1")
        }
        StubURLProtocol.stub("https://example.com/img1.jpg", data: imageBytes)
        let transport = makeTransport(client)

        do {
            _ = try await transport.fetch(id: "img1")
            XCTFail("初回はエラーになるべき")
        } catch {}

        _ = try await transport.fetch(id: "img1")
        XCTAssertEqual(client.executedPaths.count, 2, "失敗はキャッシュされず再取得される")
    }

    func testNon2xxDownloadIsReportedAsAFetchFailure() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("img1") }
        StubURLProtocol.stub("https://example.com/img1.jpg", data: Data("<html>404</html>".utf8), statusCode: 404)

        do {
            _ = try await makeTransport(client).fetch(id: "img1")
            XCTFail("404 の本文を画像として扱ってはいけない")
        } catch let error as URLImageTransportError {
            guard case .unexpectedStatus(let code, _) = error else {
                return XCTFail("想定外のエラー: \(error)")
            }
            XCTAssertEqual(code, 404)
        }
    }

    func testMalformedResourceURLThrowsInsteadOfCrashing() async throws {
        // 3.x はここで fatalError していた。相手が壊れた値を返しただけでアプリが落ちる
        let client = MockAPIClient()
        client.stubResource { _ in ImageResourceDTO(id: "img1", url: "") }

        do {
            _ = try await makeTransport(client).fetch(id: "img1")
            XCTFail("URL にできない値が通っている")
        } catch let error as URLImageTransportError {
            XCTAssertEqual(error, .malformedResourceURL(id: "img1", url: ""))
        }
    }

    // MARK: - アップロード

    func testUploadSendsMultipartAndReturnsTheId() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("up1") }

        let id = try await makeTransport(client).upload(imageBytes, contentType: "image/png")

        XCTAssertEqual(id, "up1")
        let recorded = try XCTUnwrap(client.recorded.first)
        XCTAssertEqual(recorded.path, "/images")
        XCTAssertTrue(
            recorded.contentType?.hasPrefix("multipart/form-data; boundary=") == true,
            "Content-Type が multipart になっていない: \(recorded.contentType ?? "nil")"
        )
        let body = try XCTUnwrap(recorded.body)
        XCTAssertTrue(body.range(of: imageBytes) != nil, "画像バイト列がそのまま本体に載るべき（Base64 化しない）")
    }

    func testUploadPrimesTheURLCache() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("up1") }
        StubURLProtocol.stub("https://example.com/up1.jpg", data: imageBytes)
        let transport = makeTransport(client)

        _ = try await transport.upload(imageBytes, contentType: "image/jpeg")
        _ = try await transport.fetch(id: "up1")

        XCTAssertEqual(client.executedPaths, ["/images"], "上げた直後の取得はメタデータ API を叩かない")
    }

    // MARK: - 削除

    func testDeleteEvictsTheURLCache() async throws {
        let client = MockAPIClient()
        client.stubResource { _ in self.dto("img1") }
        StubURLProtocol.stub("https://example.com/img1.jpg", data: imageBytes)
        let transport = makeTransport(client)

        _ = try await transport.fetch(id: "img1")
        try await transport.delete(id: "img1")
        _ = try await transport.fetch(id: "img1")

        XCTAssertEqual(
            client.executedPaths,
            ["/images/img1", "/images/img1", "/images/img1"],
            "削除後の取得は URL を引き直すべき"
        )
    }
}
