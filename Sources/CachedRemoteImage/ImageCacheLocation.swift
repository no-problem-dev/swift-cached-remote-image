import Foundation

/// Where the disk cache lives on the file system.
///
/// The app and its widget extension resolve their directory from the same value. When each side
/// builds a path of its own instead, a one-character difference leaves the widget permanently
/// blank while the app still looks correct. Passing the location around as a value removes that
/// failure entirely.
public enum ImageCacheLocation: Sendable, Equatable {
    /// The user's Caches directory (the default).
    ///
    /// The system may evict these files when storage runs low, which is fine for an app on its
    /// own. A widget extension cannot read them, so use ``appGroup(_:subdirectory:)`` if you
    /// ship one.
    case caches

    /// A directory inside an App Group container.
    ///
    /// The only place a widget extension can read. The system never reclaims it, so the ceiling
    /// has to be yours: set it through ``ImageLibraryConfiguration/diskCacheSizeLimit``.
    ///
    /// - Parameters:
    ///   - identifier: The App Group identifier, such as `group.com.example.app`.
    ///   - subdirectory: The directory name to use inside the container.
    case appGroup(_ identifier: String, subdirectory: String = "CachedRemoteImage")

    /// An explicit directory, for tests and for apps with their own file layout conventions.
    case directory(URL)

    /// Resolves the directory, creating it if it does not exist yet.
    ///
    /// - Throws: ``ImageCacheLocationError`` when the container cannot be resolved. A missing App
    ///   Group entitlement surfaces here; quietly falling back to another directory would leave
    ///   the widget blank with no way to find out why.
    func resolvedDirectory() throws -> URL {
        let directory: URL
        switch self {
        case .caches:
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                throw ImageCacheLocationError.cachesUnavailable
            }
            directory = caches.appendingPathComponent("CachedRemoteImage", isDirectory: true)
        case .appGroup(let identifier, let subdirectory):
            guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                throw ImageCacheLocationError.appGroupUnavailable(identifier: identifier)
            }
            directory = container.appendingPathComponent(subdirectory, isDirectory: true)
        case .directory(let url):
            directory = url
        }

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}

/// Why the disk cache directory could not be resolved.
public enum ImageCacheLocationError: Error, Equatable, Sendable {
    /// The App Group container could not be resolved.
    ///
    /// Almost always a missing entitlement or a misspelled identifier rather than a runtime
    /// condition, so it is worth failing loudly at startup instead of recovering from.
    case appGroupUnavailable(identifier: String)

    /// The system reported no Caches directory.
    ///
    /// Effectively unreachable from an app process; treat it as a broken environment.
    case cachesUnavailable
}

extension ImageCacheLocationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let identifier):
            return "App Group '\(identifier)' のコンテナを解決できない（entitlement か識別子を確認する）"
        case .cachesUnavailable:
            return "Caches ディレクトリを解決できない"
        }
    }
}
