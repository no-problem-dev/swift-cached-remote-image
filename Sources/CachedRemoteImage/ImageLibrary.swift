import Foundation

/// 画像の置き場。``ImageTransport`` を包んで、2 層キャッシュ・再試行・
/// ``CachedRemoteImage`` ビューへの供給を引き受ける。
///
/// アプリが用意するのは取り方（``ImageTransport``）だけで、
/// 「いつ取りに行くか」「どこに置くか」「いつ捨てるか」はこの型が決める。
///
/// ## 2 層の役割
/// - メモリ: 復号済みの画像。スクロール中に効くのは復号のスキップ
/// - ディスク: 受け取ったバイト列そのもの。アプリを再起動しても残り、
///   ``ImageDiskCache`` を通してウィジェットからも同期で読める
///
/// **キーは画像 ID。** 3.x のキャッシュは URL 文字列がキーだったので、
/// 公開 URL を持たないバックエンドではキャッシュに一切乗らなかった。
///
/// ## 組み立て
/// ```swift
/// let library = try ImageLibrary(
///     transport: MyImageTransport(api: api),
///     configuration: .appGroup("group.com.example.app")
/// )
///
/// // SwiftUI に渡す
/// ContentView().imageLibrary(library)
/// ```
public final class ImageLibrary: Sendable {
    private let transport: any ImageTransport
    private let diskCache: ImageDiskCache
    private let memoryCache: ImageMemoryCache
    private let retryPolicy: RetryPolicy
    private let urlSession: URLSession

    /// - Parameters:
    ///   - transport: 画像バイト列の出し入れ。アプリが実装する
    ///   - configuration: キャッシュと再試行の設定
    /// - Throws: ディスクキャッシュの置き場所を解決できないとき（``ImageCacheLocationError``）。
    ///   App Group の entitlement 忘れをここで落とす。黙って別の場所に置くと、
    ///   ウィジェットが何も表示できない理由が最後まで分からなくなる
    public init(
        transport: any ImageTransport,
        configuration: ImageLibraryConfiguration = .standard
    ) throws {
        self.transport = transport
        self.diskCache = try ImageDiskCache(
            location: configuration.cacheLocation,
            sizeLimit: configuration.diskCacheSizeLimit
        )
        self.memoryCache = ImageMemoryCache(
            countLimit: configuration.memoryCountLimit,
            costLimit: configuration.memoryCostLimit
        )
        self.retryPolicy = configuration.retryPolicy
        self.urlSession = configuration.urlSession
    }

    // MARK: - 表示のための取得

    /// 画像 ID から表示できる画像を得る。
    ///
    /// メモリ → ディスク → ``ImageTransport/fetch(id:)`` の順に見る。
    ///
    /// - Throws: ``ImageLoadError``。取得の失敗は原因の説明つきで
    ///   ``ImageLoadError/transportFailed(reason:)`` に包まれる。
    ///   transport が投げた型そのものを取り出す必要があるなら、その分岐は transport を書いた側で行う
    ///   （投げたのはアプリ自身なので、そこが一番情報を持っている）
    @MainActor
    public func image(for id: String) async throws -> PlatformImage {
        let key = ImageCacheKey.id(id)
        if let cached = memoryCache.image(for: key) {
            return cached
        }
        let data = try await imageData(for: id)
        return try decode(data, for: key)
    }

    /// URL から表示できる画像を得る。
    ///
    /// 認証の要らない外部画像（検索結果のサムネイルなど）向け。
    /// ``ImageTransport`` は通らない — URL は宛先を自分で名乗っているので、
    /// アプリ固有の取り方を挟む余地がない。
    ///
    /// - Throws: ``ImageLoadError``
    @MainActor
    public func image(from url: URL) async throws -> PlatformImage {
        let key = ImageCacheKey.url(url.absoluteString)
        if let cached = memoryCache.image(for: key) {
            return cached
        }
        let data = try await downloadData(from: url, key: key)
        return try decode(data, for: key)
    }

    // MARK: - バイト列としての取得

    /// 画像 ID からバイト列を得る。復号もメモリキャッシュもしない。
    ///
    /// 表示せずに端末へ置いておきたい場合（``prefetch(_:)``）や、
    /// 画像として使わずに扱いたい場合に使う。
    ///
    /// - Throws: ``ImageLoadError/transportFailed(reason:)``
    public func imageData(for id: String) async throws -> Data {
        let key = ImageCacheKey.id(id)
        if let onDisk = diskCache.data(for: key) {
            return onDisk
        }
        let data = try await withRetry {
            do {
                return try await self.transport.fetch(id: id)
            } catch {
                throw ImageLoadError.transportFailed(reason: error.localizedDescription)
            }
        }
        diskCache.store(data, for: key)
        return data
    }

    /// 端末にあるバイト列を**同期で**返す。無ければ `nil`。
    ///
    /// ネットワークには行かない。WidgetKit のタイムライン生成のように
    /// 非同期の取得ができない場所のための入口。
    ///
    /// ウィジェット拡張から使う場合は、この型ではなく ``ImageDiskCache`` を直接作る
    /// （拡張側に ``ImageTransport``＝認証を持ち込まずに済む）。
    public func cachedImageData(for id: String) -> Data? {
        diskCache.imageData(for: id)
    }

    /// 表示予定の画像を先に端末へ落としておく。
    ///
    /// ウィジェットは自分で画像を取りに行けない（認証を持たせるべきではない）ので、
    /// アプリ側が同期後に「次にウィジェットへ出る画像」をここで置いておく。
    ///
    /// 復号はしない。ウィジェットが要るのはバイト列で、復号はウィジェット側で起きるため。
    ///
    /// - Parameter ids: 先読みする画像 ID
    /// - Returns: 取れなかった画像 ID。先読みの失敗は表示時に取り直せるので進行は止めないが、
    ///   何が落ちたかは呼び出し側に返す（黙って減らさない）
    @discardableResult
    public func prefetch(_ ids: [String]) async -> [String] {
        var failed: [String] = []
        for id in ids where !diskCache.contains(id) {
            do {
                _ = try await imageData(for: id)
            } catch {
                failed.append(id)
            }
        }
        return failed
    }

    // MARK: - 書き込み

    /// 画像を上げて ID を得る。
    ///
    /// 上げたバイト列はそのまま手元のキャッシュに入れる。
    /// 直後に表示するために取り直すのは、同じものを 2 度運ぶだけなので。
    ///
    /// - Throws: ``ImageTransport/upload(_:contentType:)`` が投げたものをそのまま。
    ///   表示経路と違い、ここは呼び出し側がアプリのコードなので、
    ///   表示用に丸めるより元の型が残っているほうが役に立つ
    public func add(_ data: Data, contentType: String) async throws -> String {
        let id = try await transport.upload(data, contentType: contentType)
        diskCache.store(data, for: .id(id))
        return id
    }

    /// 画像を削除し、手元のキャッシュからも落とす。
    ///
    /// - Throws: ``ImageTransport/delete(id:)`` が投げたものをそのまま
    public func remove(id: String) async throws {
        try await transport.delete(id: id)
        let key = ImageCacheKey.id(id)
        diskCache.remove(for: key)
        memoryCache.remove(for: key)
    }

    // MARK: - キャッシュ管理

    /// メモリ上の復号済み画像を捨てる。ディスクは残るので表示は再度復号するだけで済む
    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    /// ディスク上のバイト列を捨てる。次の表示はネットワークからになる
    public func clearDiskCache() {
        diskCache.removeAll()
    }

    /// ディスクキャッシュの合計サイズ（バイト）
    public func diskCacheSize() -> Int64 {
        diskCache.totalBytes()
    }

    // MARK: - Private

    @MainActor
    private func decode(_ data: Data, for key: ImageCacheKey) throws -> PlatformImage {
        guard let image = PlatformImage(data: data) else {
            // 画像にならないバイト列を置いたままにすると、
            // 以降ずっとディスクヒットして同じ失敗を返し続ける
            diskCache.remove(for: key)
            throw ImageLoadError.notAnImage(byteCount: data.count)
        }
        memoryCache.store(image, for: key)
        return image
    }

    private func downloadData(from url: URL, key: ImageCacheKey) async throws -> Data {
        if let onDisk = diskCache.data(for: key) {
            return onDisk
        }
        let data = try await withRetry {
            do {
                let (data, _) = try await self.urlSession.data(from: url)
                return data
            } catch {
                throw ImageLoadError.transportFailed(reason: error.localizedDescription)
            }
        }
        diskCache.store(data, for: key)
        return data
    }

    /// 失敗したら ``RetryPolicy`` に従って再試行する。
    ///
    /// 待機に失敗（キャンセル）したらそこで打ち切る。キャンセルされたタスクで
    /// 再試行を続けると、画面から消えた画像のためにネットワークを使い続けることになる
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < retryPolicy.maxRetries else { throw error }
                let delay = retryPolicy.delay(for: attempt)
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                attempt += 1
            }
        }
    }
}
