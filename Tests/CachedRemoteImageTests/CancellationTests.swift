import XCTest
@testable import CachedRemoteImage

/// 取り消しは失敗ではない。
///
/// 画像が画面から外れると SwiftUI は `.task` を取り消す。それが「取得に失敗した」として
/// 扱われると、利用者には見に行くのをやめただけの読み込みがエラー表示として見える。
/// さらに再試行方針が付いていると、取り消したあとに残りの試行回数を使い切る
final class CancellationTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = makeTemporaryCacheDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeLibrary(
        transport: any ImageTransport,
        retryPolicy: RetryPolicy = .none
    ) throws -> ImageLibrary {
        try ImageLibrary(
            transport: transport,
            configuration: ImageLibraryConfiguration(
                cacheLocation: .directory(directory),
                retryPolicy: retryPolicy
            )
        )
    }

    // MARK: - 取得

    func testCancelledFetchIsNotRetried() async throws {
        // 待ち時間 0 の方針だと `Task.sleep` を通らないので、取り消しが再試行ループを抜ける
        // 唯一の出口が塞がる
        let transport = ParkingImageTransport()
        let library = try makeLibrary(transport: transport, retryPolicy: .fixed(count: 3))

        let task = Task { try await library.imageData(for: "img-1") }
        try await waitUntilFetchStarted(transport)
        task.cancel()
        let result = await task.result

        XCTAssertEqual(
            transport.fetchedIds.count,
            1,
            "取り消したあとに再試行へ入っている。画面から外れた画像のために通信を続けることになる"
        )
        switch result {
        case .success:
            XCTFail("取り消した読み込みが成功として返っている")
        case .failure(let error):
            XCTAssertTrue(
                error is CancellationError,
                "取り消しが取得の失敗にすり替わっている: \(error)"
            )
        }
    }

    func testCancelledDownloadIsNotRetried() async throws {
        // URL 経路も同じ再試行ループを通る
        let transport = ParkingImageTransport()
        let library = try makeLibrary(transport: transport, retryPolicy: .fixed(count: 3))

        let task = Task { try await library.imageData(for: "img-1") }
        try await waitUntilFetchStarted(transport)
        task.cancel()
        let result = await task.result

        guard case .failure(let error) = result else {
            return XCTFail("取り消した読み込みが成功として返っている")
        }
        XCTAssertTrue(error is CancellationError, "取り消しが取得の失敗にすり替わっている: \(error)")
    }

    func testATransportThatReportsCancellationIsNotRetried() async throws {
        // 取り消しは外側の task からとは限らない。自前の期限切れを子 task の取り消しで
        // 表す transport はそのまま `CancellationError` を投げる。
        // 外側が生きているからといって取得の失敗に読み替えると、回数分やり直すことになる
        let transport = CancellingImageTransport()
        let library = try makeLibrary(transport: transport, retryPolicy: .fixed(count: 3))

        let result = await Task { try await library.imageData(for: "img-1") }.result

        XCTAssertEqual(
            transport.fetchedIds.count,
            1,
            "transport が取り消しと言ったのに再試行へ入っている"
        )
        guard case .failure(let error) = result else {
            return XCTFail("取り消した取得が成功として返っている")
        }
        XCTAssertTrue(error is CancellationError, "取り消しが取得の失敗にすり替わっている: \(error)")
    }

    // MARK: - 先読み

    func testCancelledPrefetchStopsFetching() async throws {
        let transport = ParkingImageTransport()
        let library = try makeLibrary(transport: transport)
        let ids = (1...20).map { "img-\($0)" }

        let task = Task { await library.prefetch(ids) }
        try await waitUntilFetchStarted(transport)
        task.cancel()
        _ = await task.value

        XCTAssertEqual(
            transport.fetchedIds.count,
            1,
            "取り消したのに残りの ID も取りに行っている"
        )
    }

    func testCancelledPrefetchDoesNotReportEveryIdAsFailed() async throws {
        let transport = ParkingImageTransport()
        let library = try makeLibrary(transport: transport)
        let ids = (1...20).map { "img-\($0)" }

        let task = Task { await library.prefetch(ids) }
        try await waitUntilFetchStarted(transport)
        task.cancel()
        let failures = await task.value

        XCTAssertLessThan(
            failures.count,
            ids.count,
            "取り消しただけなのに全 ID が「取得できなかった」として返っている"
        )
    }

    // MARK: - ビューの状態

    @MainActor
    func testCancelledLoadDoesNotBecomeAnErrorView() async throws {
        let transport = ParkingImageTransport()
        let loader = CachedRemoteImageLoader(
            library: try makeLibrary(transport: transport),
            source: .imageId("img-1")
        )

        let task = Task { await loader.load() }
        try await waitUntilFetchStarted(transport)
        task.cancel()
        await task.value

        XCTAssertNil(
            loader.state.error,
            "画面から外しただけでエラー表示に落ちている: \(loader.state)"
        )
    }

    @MainActor
    func testCancelledLoadCanBeStartedAgain() async throws {
        // 取り消しで .failure に落ちると `load()` の入口ガードに弾かれ、
        // 同じビューがもう一度出てきても二度と読み込まれない
        let transport = ParkingImageTransport()
        let loader = CachedRemoteImageLoader(
            library: try makeLibrary(transport: transport),
            source: .imageId("img-1")
        )

        let task = Task { await loader.load() }
        try await waitUntilFetchStarted(transport)
        task.cancel()
        await task.value

        XCTAssertEqual(loader.state, .idle, "取り消し後は最初から読み直せる状態に戻すべき")
    }

}

/// `fetch` に入ったところまで進むのを待つ。取り消しを「取得が始まる前」に打つと
/// 何も確かめられないので、開始を観測してから取り消す
private func waitUntilFetchStarted(
    _ transport: ParkingImageTransport,
    timeout: TimeInterval = 5,
    file: StaticString = #filePath,
    line: UInt = #line
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while transport.fetchedIds.isEmpty {
        if Date() > deadline {
            XCTFail("取得が始まらなかった", file: file, line: line)
            return
        }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
}

// MARK: - テストダブル

/// 取り消されるまで `fetch` が返らない ``ImageTransport``。
///
/// 画面に出ている間に読み込みが終わらず、画面から外れて取り消される、という実際の並びを作る。
/// `Task.sleep` を取り消し地点にしているので、`URLSession` が投げるものと同じく
/// `CancellationError` が出る
final class ParkingImageTransport: ImageTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _fetchedIds: [String] = []

    var fetchedIds: [String] { lock.withLock { _fetchedIds } }

    func fetch(id: String) async throws -> Data {
        lock.withLock { _fetchedIds.append(id) }
        try await Task.sleep(nanoseconds: 30_000_000_000)
        return TestImage.pngData()
    }

    func upload(_ data: Data, contentType: String) async throws -> String { "unused" }

    func delete(id: String) async throws {}
}

/// 呼ばれた時点で取り消しを報告する ``ImageTransport``。
///
/// 自前の期限切れを子 task の取り消しで表す作りだと、外側の task が生きたまま
/// `CancellationError` が出てくる
final class CancellingImageTransport: ImageTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _fetchedIds: [String] = []

    var fetchedIds: [String] { lock.withLock { _fetchedIds } }

    func fetch(id: String) async throws -> Data {
        lock.withLock { _fetchedIds.append(id) }
        throw CancellationError()
    }

    func upload(_ data: Data, contentType: String) async throws -> String { "unused" }

    func delete(id: String) async throws {}
}
