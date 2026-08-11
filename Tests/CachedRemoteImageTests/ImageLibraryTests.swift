import XCTest
@testable import CachedRemoteImage

/// ``ImageLibrary`` の要点は「アプリが取り方を与え、キャッシュはパッケージが持つ」。
/// 取り方が差し替わっても同じキャッシュが効き、キャッシュが効いている間は取り方を呼ばない
final class ImageLibraryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = makeTemporaryCacheDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.reset()
    }

    private func makeLibrary(
        transport: FakeImageTransport,
        retryPolicy: RetryPolicy = .none,
        diskCacheSizeLimit: Int64 = 100 * 1024 * 1024,
        urlSession: URLSession = .shared
    ) throws -> ImageLibrary {
        try ImageLibrary(
            transport: transport,
            configuration: ImageLibraryConfiguration(
                cacheLocation: .directory(directory),
                diskCacheSizeLimit: diskCacheSizeLimit,
                retryPolicy: retryPolicy,
                urlSession: urlSession
            )
        )
    }

    // MARK: - 画像 ID 経路がキャッシュに乗る（3.x で欠けていたところ）

    @MainActor
    func testImageForIdGoesThroughTheTransport() async throws {
        let bytes = TestImage.pngData()
        let transport = FakeImageTransport(behavior: .succeeding(bytes))
        let library = try makeLibrary(transport: transport)

        let image = try await library.image(for: "img-1")

        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertEqual(transport.fetchedIds, ["img-1"])
    }

    @MainActor
    func testSecondLoadOfSameIdDoesNotTouchTheTransport() async throws {
        let transport = FakeImageTransport()
        let library = try makeLibrary(transport: transport)

        _ = try await library.image(for: "img-1")
        _ = try await library.image(for: "img-1")

        XCTAssertEqual(transport.fetchedIds, ["img-1"], "2 回目はキャッシュが応答すべき")
    }

    func testBytesSurviveIntoAFreshLibraryOverTheSameDirectory() async throws {
        let bytes = TestImage.pngData(width: 8, height: 8)
        let writer = FakeImageTransport(behavior: .succeeding(bytes))
        _ = try await makeLibrary(transport: writer).imageData(for: "img-1")

        // アプリ再起動に相当。ディスクに乗っているなら transport は呼ばれない
        let reader = FakeImageTransport(behavior: .failing)
        let restored = try await makeLibrary(transport: reader).imageData(for: "img-1")

        XCTAssertEqual(restored, bytes)
        XCTAssertTrue(reader.fetchedIds.isEmpty, "ディスクにあるなら取りに行かないべき")
    }

    func testDifferentIdsAreCachedIndependently() async throws {
        let transport = FakeImageTransport()
        let library = try makeLibrary(transport: transport)

        _ = try await library.imageData(for: "a")
        _ = try await library.imageData(for: "b")
        _ = try await library.imageData(for: "a")

        XCTAssertEqual(transport.fetchedIds, ["a", "b"])
    }

    // MARK: - 取り方の差し替え

    func testSwappingTheTransportChangesWhatIsFetched() async throws {
        let first = Data("from-first-backend".utf8)
        let second = Data("from-second-backend".utf8)

        let a = try await makeLibrary(transport: FakeImageTransport(behavior: .succeeding(first)))
            .imageData(for: "img-1")

        // 別のディレクトリ＝別の置き場にして、キャッシュではなく transport の差が出るようにする
        directory = makeTemporaryCacheDirectory()
        let b = try await makeLibrary(transport: FakeImageTransport(behavior: .succeeding(second)))
            .imageData(for: "img-1")

        XCTAssertEqual(a, first)
        XCTAssertEqual(b, second)
    }

    // MARK: - ウィジェット向けの同期読み

    func testCachedImageDataReturnsBytesAfterFetch() async throws {
        let bytes = TestImage.pngData()
        let library = try makeLibrary(transport: FakeImageTransport(behavior: .succeeding(bytes)))
        _ = try await library.imageData(for: "img-1")

        XCTAssertEqual(library.cachedImageData(for: "img-1"), bytes)
    }

    func testCachedImageDataNeverGoesToTheTransport() throws {
        // WidgetKit のタイムライン生成は非同期取得ができない。
        // ここがネットワークに出ると、ウィジェットが取得待ちで固まる
        let transport = FakeImageTransport()
        let library = try makeLibrary(transport: transport)

        XCTAssertNil(library.cachedImageData(for: "never-fetched"))
        XCTAssertTrue(transport.fetchedIds.isEmpty, "同期読みは取得に出てはいけない")
    }

    func testWidgetSideDiskCacheSeesWhatTheLibraryStored() async throws {
        let bytes = TestImage.pngData()
        let library = try makeLibrary(transport: FakeImageTransport(behavior: .succeeding(bytes)))
        _ = try await library.imageData(for: "img-1")

        // ウィジェット拡張は transport を持たず、同じ場所を指す ImageDiskCache だけを作る
        let widgetSide = try ImageDiskCache(location: .directory(directory))
        XCTAssertEqual(widgetSide.imageData(for: "img-1"), bytes)
    }

    // MARK: - 先読み

    func testPrefetchPutsBytesOnDisk() async throws {
        let transport = FakeImageTransport()
        let library = try makeLibrary(transport: transport)

        let failed = await library.prefetch(["a", "b"])

        XCTAssertEqual(failed, [:])
        XCTAssertNotNil(library.cachedImageData(for: "a"))
        XCTAssertNotNil(library.cachedImageData(for: "b"))
    }

    func testPrefetchSkipsWhatIsAlreadyOnDisk() async throws {
        let transport = FakeImageTransport()
        let library = try makeLibrary(transport: transport)
        _ = try await library.imageData(for: "a")

        await library.prefetch(["a", "b"])

        XCTAssertEqual(transport.fetchedIds, ["a", "b"], "既にある a を取り直さないべき")
    }

    func testPrefetchReportsWhatItCouldNotGet() async throws {
        let library = try makeLibrary(transport: FakeImageTransport(behavior: .failing))

        let failed = await library.prefetch(["a", "b"])

        XCTAssertEqual(Set(failed.keys), ["a", "b"], "落ちた ID を黙って捨てないべき")
    }

    func testPrefetchReportsWhyEachIdCouldNotBeGot() async throws {
        // ID だけ返ると、期限切れのトークンで落ちたのか、その画像がもう無いのかが区別できない。
        // 呼び出し側は「何が足りないか」は分かっても「どうすればいいか」が分からない
        let library = try makeLibrary(transport: FakeImageTransport(behavior: .failing))

        let failed = await library.prefetch(["a"])

        guard case .transportFailed(let reason) = failed["a"] else {
            return XCTFail("落ちた理由が捨てられている: \(String(describing: failed["a"]))")
        }
        XCTAssertTrue(
            reason.contains("fake transport is failing"),
            "transport が言った理由がそのまま残っているべき: \(reason)"
        )
    }

    // MARK: - 失敗の伝え方

    func testTransportFailureSurfacesAsTransportFailed() async throws {
        let library = try makeLibrary(transport: FakeImageTransport(behavior: .failing))

        do {
            _ = try await library.imageData(for: "img-1")
            XCTFail("取得の失敗が握りつぶされている")
        } catch let error as ImageLoadError {
            guard case .transportFailed(let reason) = error else {
                return XCTFail("想定外のエラー: \(error)")
            }
            XCTAssertFalse(reason.isEmpty, "原因の説明が残っているべき")
        }
    }

    func testTransportFailureKeepsWhatTheTransportSaid() async throws {
        // 既存の「reason が空でない」だけの検査はここを通してしまう。
        // `localizedDescription` は LocalizedError でない Swift のエラーに対して
        // 「操作を完了できませんでした。（型名 エラー 1）」という定型文しか返さないので、
        // reason は空にならないまま中身だけが消える。しかも端末の言語で文面が変わる
        let library = try makeLibrary(transport: FakeImageTransport(behavior: .failing))

        do {
            _ = try await library.imageData(for: "img-1")
            XCTFail("取得の失敗が握りつぶされている")
        } catch let error as ImageLoadError {
            guard case .transportFailed(let reason) = error else {
                return XCTFail("想定外のエラー: \(error)")
            }
            XCTAssertTrue(
                reason.contains("fake transport is failing"),
                "transport が言ったことが定型文に置き換わっている: \(reason)"
            )
        }
    }

    @MainActor
    func testBytesThatAreNotAnImageSurfaceAsNotAnImage() async throws {
        let library = try makeLibrary(transport: FakeImageTransport(behavior: .succeeding(TestImage.notAnImage)))

        do {
            _ = try await library.image(for: "img-1")
            XCTFail("画像にならないバイト列が成功扱いになっている")
        } catch let error as ImageLoadError {
            XCTAssertEqual(error, .notAnImage(byteCount: TestImage.notAnImage.count))
        }
    }

    @MainActor
    func testBytesThatAreNotAnImageAreEvictedFromDisk() async throws {
        let library = try makeLibrary(transport: FakeImageTransport(behavior: .succeeding(TestImage.notAnImage)))

        _ = try? await library.image(for: "img-1")

        XCTAssertNil(
            library.cachedImageData(for: "img-1"),
            "画像にならないバイト列を残すと、以降ずっと同じ失敗を返し続ける"
        )
    }

    // MARK: - 再試行

    func testFetchIsRetriedUntilItSucceeds() async throws {
        let bytes = TestImage.pngData()
        let transport = FakeImageTransport(behavior: .failingTimes(2, then: bytes))
        let library = try makeLibrary(transport: transport, retryPolicy: .fixed(count: 2))

        let data = try await library.imageData(for: "img-1")

        XCTAssertEqual(data, bytes)
        XCTAssertEqual(transport.fetchedIds.count, 3, "2 回失敗したあと 3 回目で成功するはず")
    }

    func testWithoutARetryPolicyTheFirstFailureIsFinal() async throws {
        let transport = FakeImageTransport(behavior: .failingTimes(1, then: TestImage.pngData()))
        let library = try makeLibrary(transport: transport, retryPolicy: .none)

        _ = try? await library.imageData(for: "img-1")

        XCTAssertEqual(transport.fetchedIds.count, 1)
    }

    func testRetryGivesUpAfterTheConfiguredCount() async throws {
        let transport = FakeImageTransport(behavior: .failing)
        let library = try makeLibrary(transport: transport, retryPolicy: .fixed(count: 2))

        _ = try? await library.imageData(for: "img-1")

        XCTAssertEqual(transport.fetchedIds.count, 3, "初回 + 再試行 2 回で打ち切るべき")
    }

    @MainActor
    func testDecodingFailureIsNotRetried() async throws {
        // 同じバイト列を何度復号しても結果は変わらない
        let transport = FakeImageTransport(behavior: .succeeding(TestImage.notAnImage))
        let library = try makeLibrary(transport: transport, retryPolicy: .fixed(count: 3))

        _ = try? await library.image(for: "img-1")

        XCTAssertEqual(transport.fetchedIds.count, 1)
    }

    // MARK: - 書き込み

    func testAddUploadsThroughTheTransportAndKeepsTheBytes() async throws {
        let transport = FakeImageTransport()
        transport.uploadResultId = "new-id"
        let library = try makeLibrary(transport: transport)
        let bytes = TestImage.pngData()

        let id = try await library.add(bytes, contentType: "image/png")

        XCTAssertEqual(id, "new-id")
        XCTAssertEqual(transport.uploaded.first?.contentType, "image/png")
        XCTAssertEqual(
            library.cachedImageData(for: "new-id"),
            bytes,
            "上げたバイト列は手元にあるので、表示のために取り直す必要はない"
        )
    }

    func testRemoveDeletesThroughTheTransportAndEvictsTheCache() async throws {
        let transport = FakeImageTransport()
        let library = try makeLibrary(transport: transport)
        _ = try await library.imageData(for: "img-1")

        try await library.remove(id: "img-1")

        XCTAssertEqual(transport.deletedIds, ["img-1"])
        XCTAssertNil(library.cachedImageData(for: "img-1"))
    }

    // MARK: - キャッシュ管理

    func testClearDiskCacheEmptiesTheDirectory() async throws {
        let library = try makeLibrary(transport: FakeImageTransport())
        _ = try await library.imageData(for: "img-1")
        XCTAssertGreaterThan(library.diskCacheSize(), 0)

        library.clearDiskCache()

        XCTAssertEqual(library.diskCacheSize(), 0)
        XCTAssertNil(library.cachedImageData(for: "img-1"))
    }

    // MARK: - URL 直接指定

    @MainActor
    func testImageFromURLIsServedFromMemoryOnSecondLoad() async throws {
        let url = URL(string: "https://example.com/cover.png")!
        StubURLProtocol.stub(url.absoluteString, data: TestImage.pngData())

        let transport = FakeImageTransport()
        let library = try makeLibrary(transport: transport, urlSession: StubURLProtocol.makeSession())

        _ = try await library.image(from: url)
        _ = try await library.image(from: url)

        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1, "2 回目はメモリキャッシュが応答すべき")
        XCTAssertTrue(transport.fetchedIds.isEmpty, "URL 経路は ImageTransport を通らない")
    }

    @MainActor
    func testImageFromURLIsServedFromDiskAfterMemoryIsCleared() async throws {
        // メモリを消してもディスクに残っている必要がある。
        // メモリだけで確かめると、ディスク層が無くてもテストが通ってしまう
        let url = URL(string: "https://example.com/cover.png")!
        StubURLProtocol.stub(url.absoluteString, data: TestImage.pngData())
        let library = try makeLibrary(
            transport: FakeImageTransport(),
            urlSession: StubURLProtocol.makeSession()
        )

        _ = try await library.image(from: url)
        library.clearMemoryCache()
        _ = try await library.image(from: url)

        XCTAssertEqual(StubURLProtocol.requestedURLs.count, 1, "ディスクに残っているなら取り直さないべき")
    }

    @MainActor
    func testImageFromURLReportsDownloadFailure() async throws {
        let library = try makeLibrary(
            transport: FakeImageTransport(),
            urlSession: StubURLProtocol.makeSession()
        )

        do {
            _ = try await library.image(from: URL(string: "https://example.com/missing.png")!)
            XCTFail("ダウンロードの失敗が握りつぶされている")
        } catch let error as ImageLoadError {
            guard case .transportFailed = error else {
                return XCTFail("想定外のエラー: \(error)")
            }
        }
    }
}
