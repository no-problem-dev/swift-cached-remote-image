import Foundation

/// Where a view gets its image from, and therefore which of the two fetch paths it takes.
///
/// The two paths keep separate cache key spaces, so an id that happens to read like a URL cannot
/// collide with a real one.
///
/// ## Examples
/// ```swift
/// // Through the transport your app implements
/// CachedRemoteImage(source: .imageId("abc123"))
///
/// // Straight from a URL, for images that need no authentication
/// CachedRemoteImage(source: .url(imageURL))
///
/// // The same, given as a string
/// CachedRemoteImage(source: .urlString("https://example.com/image.jpg"))
/// ```
public enum ImageSource: Equatable, Sendable, Hashable {
    /// Fetched through the transport your app supplies, and cached under that id.
    ///
    /// The only source that reaches ``ImageTransport``.
    case imageId(String)

    /// Downloaded with the configured session, never through the transport.
    case url(URL)

    /// A URL given as a string, which takes the same path once it parses.
    ///
    /// Behaves exactly like ``url(_:)`` from there on. A string that is not a valid URL surfaces
    /// as ``ImageLoadError/invalidURL(_:)`` in the error view, rather than as an image that never
    /// appears.
    case urlString(String)
}
