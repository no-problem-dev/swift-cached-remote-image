import XCTest
@testable import CachedRemoteImage

/// ビューが持つ状態機械。失敗が状態に載らないと、画面に何も出ない理由がどこにも残らない
final class CachedRemoteImageLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = makeTemporaryCacheDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.reset()
    }

    private func makeLibrary(
        transport: FakeImageTransport = FakeImageTransport(),
        urlSession: URLSession = .shared
    ) throws -> ImageLibrary {
        try ImageLibrary(
            transport: transport,
            configuration: ImageLibraryConfiguration(
                cacheLocation: .directory(directory),
                urlSession: urlSession
            )
        )
    }

    @MainActor
    func testMissingLibraryBecomesAVisibleFailure() async throws {
        // 3.x はここで print して素通りしていた。画像が出ない理由がコンソールにしか残らない
        let loader = CachedRemoteImageLoader(library: nil, source: .imageId("img-1"))

        await loader.load()

        XCTAssertEqual(loader.state, .failure(.libraryNotConfigured))
    }

    @MainActor
    func testImageIdSourceLoadsThroughTheLibrary() async throws {
        let transport = FakeImageTransport()
        let loader = CachedRemoteImageLoader(
            library: try makeLibrary(transport: transport),
            source: .imageId("img-1")
        )

        await loader.load()

        XCTAssertTrue(loader.state.isSuccess)
        XCTAssertEqual(transport.fetchedIds, ["img-1"])
    }

    @MainActor
    func testTransportFailureBecomesFailureState() async throws {
        let loader = CachedRemoteImageLoader(
            library: try makeLibrary(transport: FakeImageTransport(behavior: .failing)),
            source: .imageId("img-1")
        )

        await loader.load()

        guard case .failure(.transportFailed) = loader.state else {
            return XCTFail("想定外の状態: \(loader.state)")
        }
    }

    @MainActor
    func testMalformedURLStringBecomesInvalidURL() async throws {
        let loader = CachedRemoteImageLoader(
            library: try makeLibrary(),
            source: .urlString("")
        )

        await loader.load()

        XCTAssertEqual(loader.state, .failure(.invalidURL("")))
    }

    @MainActor
    func testURLStringSourceLoadsThroughTheLibrary() async throws {
        let url = "https://example.com/cover.png"
        StubURLProtocol.stub(url, data: TestImage.pngData())
        let loader = CachedRemoteImageLoader(
            library: try makeLibrary(urlSession: StubURLProtocol.makeSession()),
            source: .urlString(url)
        )

        await loader.load()

        XCTAssertTrue(loader.state.isSuccess)
    }
}
