import Foundation

/// Synchronous, network-free access to the image bytes already on this device.
///
/// WidgetKit's timeline generation has nowhere to put an async network call, so a widget needs an
/// entry point that answers with whatever is on disk right now. This type has no way to reach the
/// network at all, so holding one cannot stall a timeline on a fetch.
///
/// The app itself uses ``ImageLibrary``, which owns one of these internally. A widget builds its
/// own and passes the same ``ImageCacheLocation`` value the app used.
///
/// ## Reading from a widget
/// ```swift
/// let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))
/// if let data = cache.imageData(for: item.imageId), let image = UIImage(data: data) {
///     Image(uiImage: image)
/// } else {
///     Text(item.emoji)   // always have somewhere to land
/// }
/// ```
///
/// ## What gets stored
/// Entries are written exactly as they arrived, with no decode-and-re-encode step. PNG
/// transparency therefore survives, and a widget reads the real file rather than a lossy copy of
/// it. Nothing here is decoded — that cost is paid by whoever displays the image.
public struct ImageDiskCache: Sendable {
    private let directory: URL
    private let sizeLimit: Int64

    /// - Parameters:
    ///   - location: Where the files are kept. Use ``ImageCacheLocation/appGroup(_:subdirectory:)``
    ///     to share them with a widget.
    ///   - sizeLimit: Maximum bytes to keep. Once the total passes it, the oldest entries are
    ///     deleted until it fits again.
    /// - Throws: ``ImageCacheLocationError`` when the directory cannot be resolved or created,
    ///   such as when the App Group entitlement is missing.
    public init(location: ImageCacheLocation = .caches, sizeLimit: Int64 = 100 * 1024 * 1024) throws {
        self.directory = try location.resolvedDirectory()
        self.sizeLimit = sizeLimit
    }

    /// Returns the cached bytes for an image synchronously, or `nil` when they are not on disk.
    ///
    /// Never touches the network, so `nil` means exactly one thing: those bytes have not reached
    /// this device yet.
    ///
    /// - Parameter id: The image id the bytes were stored under.
    public func imageData(for id: String) -> Data? {
        data(for: .id(id))
    }

    /// Reports whether an image's bytes are on disk, without reading them into memory.
    public func contains(_ id: String) -> Bool {
        contains(.id(id))
    }

    /// The total size of the cached files in bytes, measured by walking the directory.
    public func totalBytes() -> Int64 {
        entries().reduce(Int64(0)) { $0 + $1.size }
    }

    /// Deletes every cached file. Each image is then fetched again the next time it is displayed.
    public func removeAll() {
        guard let contents = try? FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Internal (kept apart from the public API so URL-keyed entries can be stored too)

    func data(for key: ImageCacheKey) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func contains(_ key: ImageCacheKey) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: key).path)
    }

    /// Writes the bytes, then evicts the oldest entries if the total is now over the limit.
    ///
    /// Writes only ever follow a network round trip, so scanning the directory each time is
    /// buried in that cost. Tracking the written size separately to avoid the scan would go wrong
    /// the moment a second process touched the same directory — which is exactly what an app and
    /// its widget do.
    func store(_ data: Data, for key: ImageCacheKey) {
        try? data.write(to: fileURL(for: key), options: .atomic)
        trimToSizeLimit()
    }

    func remove(for key: ImageCacheKey) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    // MARK: - Private

    private func fileURL(for key: ImageCacheKey) -> URL {
        directory.appendingPathComponent(key.fileName)
    }

    private struct Entry {
        let url: URL
        let size: Int64
        let modifiedAt: Date
    }

    private func entries() -> [Entry] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else {
            return []
        }
        return contents.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize else { return nil }
            return Entry(url: url, size: Int64(size), modifiedAt: values.contentModificationDate ?? .distantPast)
        }
    }

    /// Deletes entries oldest-first until the total fits inside the size limit.
    ///
    /// The system never reclaims an App Group container, even under storage pressure. Without a
    /// ceiling of our own, the space used would grow with every image viewed and never come back.
    private func trimToSizeLimit() {
        let all = entries()
        var total = all.reduce(Int64(0)) { $0 + $1.size }
        guard total > sizeLimit else { return }

        for entry in all.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            guard total > sizeLimit else { break }
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}
