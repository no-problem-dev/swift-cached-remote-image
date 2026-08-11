import Foundation

/// Owns an app's cached images: two cache layers, the retry policy, and the fetches behind the view.
///
/// Your app supplies only the way bytes are fetched, as an ``ImageTransport``. When to go to the
/// network, where a result is kept and when it is discarded are decided here.
///
/// ## The two layers
/// - Memory holds decoded images. What it saves during a scroll is decoding, not file reads. It
///   is emptied when the process ends, and the system may evict entries under memory pressure.
/// - Disk holds the bytes as they arrived. They survive a relaunch, and a widget can read them
///   synchronously through ``ImageDiskCache``.
///
/// **Everything is keyed by image id**, so a backend that never exposes a public URL still gets
/// the full benefit of both layers.
///
/// ## Building one
/// ```swift
/// let library = try ImageLibrary(
///     transport: MyImageTransport(api: api),
///     configuration: .appGroup("group.com.example.app")
/// )
///
/// // Hand it to SwiftUI
/// ContentView().imageLibrary(library)
/// ```
public final class ImageLibrary: Sendable {
    private let transport: any ImageTransport
    private let diskCache: ImageDiskCache
    private let memoryCache: ImageMemoryCache
    private let retryPolicy: RetryPolicy
    private let urlSession: URLSession

    /// - Parameters:
    ///   - transport: How image bytes are fetched, uploaded and deleted. Your app implements it.
    ///   - configuration: Cache placement, size limits and retry policy, fixed for the lifetime
    ///     of this library.
    /// - Throws: ``ImageCacheLocationError`` when the disk cache directory cannot be resolved. A
    ///   missing App Group entitlement lands here. Falling back to some other directory instead
    ///   would leave the widget permanently blank with no way to find out why.
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

    // MARK: - Fetching for display

    /// Returns a displayable image for an image id, going to the network only as a last resort.
    ///
    /// Looks in memory, then on disk, then calls ``ImageTransport/fetch(id:)``. A fetched image
    /// lands in both layers, so the next call for the same id is a memory hit.
    ///
    /// - Throws: ``ImageLoadError``. A failing transport arrives as
    ///   ``ImageLoadError/transportFailed(reason:)`` with its description preserved. Code that
    ///   needs the concrete error type back — to catch an expired session and send the user to
    ///   sign-in — belongs in the transport, which threw it and holds the most information.
    @MainActor
    public func image(for id: String) async throws -> PlatformImage {
        let key = ImageCacheKey.id(id)
        if let cached = memoryCache.image(for: key) {
            return cached
        }
        let data = try await imageData(for: id)
        return try decode(data, for: key)
    }

    /// Returns a displayable image for a URL, without involving the transport.
    ///
    /// For images that need no authentication, such as search-result thumbnails: a URL already
    /// names its own destination, so there is no app-specific fetching to inject. Downloads use
    /// the session from the configuration, and results are cached under the URL in a key space of
    /// their own, apart from image ids.
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

    // MARK: - Fetching raw bytes

    /// Returns the bytes for an image id, skipping both the decode step and the memory cache.
    ///
    /// Checks disk, then the transport, and writes what it fetched back to disk. Use it to put an
    /// image on the device without showing it, as ``prefetch(_:)`` does, or to treat the bytes as
    /// something other than an image.
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
            } catch is CancellationError {
                // Cancellation is not a failure to fetch. Relabelling it here would put
                // "Couldn't load the image" in front of someone who only scrolled away.
                throw CancellationError()
            } catch {
                throw ImageLoadError.transportFailed(wrapping: error)
            }
        }
        diskCache.store(data, for: key)
        return data
    }

    /// Returns bytes already on this device synchronously, or `nil` when they are not there.
    ///
    /// Never touches the network. This is the entry point for places that cannot await a fetch,
    /// such as WidgetKit timeline generation.
    ///
    /// From a widget extension, build ``ImageDiskCache`` directly rather than this type: that
    /// keeps the transport, and therefore your credentials, out of the extension.
    public func cachedImageData(for id: String) -> Data? {
        diskCache.imageData(for: id)
    }

    /// Downloads images to disk ahead of time, skipping ids already cached.
    ///
    /// A widget cannot fetch its own images, so after a sync the app puts whatever the widget
    /// will show next on disk. Nothing is decoded here: what a widget needs is bytes, and the
    /// decoding happens on its side.
    ///
    /// - Parameter ids: The image ids to download.
    /// - Returns: The ids that could not be downloaded, each with the reason it could not be.
    ///   A failed prefetch is recoverable at display time, so one failure does not stop the rest,
    ///   and the reason travels with the id: an expired session and a deleted image both leave an
    ///   id missing, but only one of them is worth sending the user to sign-in over.
    ///
    ///   Cancelling the task stops the walk where it stands, and the ids never reached are left
    ///   out rather than reported as failures they never had.
    @discardableResult
    public func prefetch(_ ids: [String]) async -> [String: ImageLoadError] {
        var failures: [String: ImageLoadError] = [:]
        for id in ids where !diskCache.contains(id) {
            if Task.isCancelled { break }
            do {
                _ = try await imageData(for: id)
            } catch is CancellationError {
                break
            } catch let error as ImageLoadError {
                failures[id] = error
            } catch {
                failures[id] = .transportFailed(wrapping: error)
            }
        }
        return failures
    }

    // MARK: - Writing

    /// Uploads bytes through the transport and returns the id assigned to them.
    ///
    /// What you uploaded goes straight into the disk cache, so displaying the image immediately
    /// afterwards does not download what this device just sent.
    ///
    /// - Throws: Whatever ``ImageTransport/upload(_:contentType:)`` threw, untouched. Unlike the
    ///   display path, the caller here is your own code, so the original type is more use than a
    ///   rounded-off one.
    public func add(_ data: Data, contentType: String) async throws -> String {
        let id = try await transport.upload(data, contentType: contentType)
        diskCache.store(data, for: .id(id))
        return id
    }

    /// Deletes an image through the transport and drops it from both cache layers.
    ///
    /// - Throws: Whatever ``ImageTransport/delete(id:)`` threw, untouched. Nothing is evicted
    ///   when the delete fails, so the caches keep matching the backend.
    public func remove(id: String) async throws {
        try await transport.delete(id: id)
        let key = ImageCacheKey.id(id)
        diskCache.remove(for: key)
        memoryCache.remove(for: key)
    }

    // MARK: - Cache management

    /// Discards the decoded images held in memory.
    ///
    /// The bytes stay on disk, so redisplaying one of them costs a decode rather than a download.
    public func clearMemoryCache() {
        memoryCache.removeAll()
    }

    /// Discards the bytes held on disk.
    ///
    /// The next display of each image goes back to the transport. Images already decoded in
    /// memory keep displaying until that layer is cleared too.
    public func clearDiskCache() {
        diskCache.removeAll()
    }

    /// The total bytes currently held on disk, measured by walking the cache directory.
    public func diskCacheSize() -> Int64 {
        diskCache.totalBytes()
    }

    // MARK: - Private

    @MainActor
    private func decode(_ data: Data, for key: ImageCacheKey) throws -> PlatformImage {
        guard let image = PlatformImage(data: data) else {
            // Leaving undecodable bytes on disk would turn every later request into a disk
            // hit that fails the same way, indefinitely.
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
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw ImageLoadError.transportFailed(wrapping: error)
            }
        }
        diskCache.store(data, for: key)
        return data
    }

    /// Runs an operation, retrying failures according to the configured retry policy.
    ///
    /// Cancellation ends the retrying immediately and travels out as `CancellationError`. Leaving
    /// it to the wait between attempts would not work: ``RetryPolicy/fixed(count:)`` waits for
    /// zero seconds, so there is no `Task.sleep` to throw, and a cancelled load would use up every
    /// attempt going to the network for an image that has already left the screen.
    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                if error is CancellationError { throw error }
                // Catches the transports that report cancellation as something else —
                // `URLSession` raises `URLError.cancelled` rather than `CancellationError`.
                try Task.checkCancellation()
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
