import Foundation

/// How your app fetches, uploads and deletes image bytes.
///
/// Authentication, endpoints and response shapes differ per app, and a package has no business
/// guessing them. Caching, retries and the SwiftUI loading lifecycle are the same everywhere. So
/// the direction is inverted: your app supplies the fetching, and ``ImageLibrary`` owns the
/// caching around it. These three methods are all you implement.
///
/// No default implementation ships with the package. Bundling one would constrain the dependency
/// resolution of everyone who never uses it, because SPM resolves dependencies per package rather
/// than per target: a dependency declared for a target you never build still enters your
/// resolution space. If your backend returns a public URL from a metadata endpoint, make
/// ``fetch(id:)`` two steps — read the metadata, then fetch the bytes from that URL.
///
/// ## Implementing it
/// ```swift
/// struct MyImageTransport: ImageTransport {
///     let api: MyAPIClient
///
///     func fetch(id: String) async throws -> Data {
///         try await api.getImage(id: id)
///     }
///
///     func upload(_ data: Data, contentType: String) async throws -> String {
///         try await api.uploadImage(data, contentType: contentType).id
///     }
///
///     func delete(id: String) async throws {
///         try await api.deleteImage(id: id)
///     }
/// }
/// ```
public protocol ImageTransport: Sendable {
    /// Fetches the bytes for an image id.
    ///
    /// Implementations need no cache of their own. This is called only once ``ImageLibrary`` has
    /// established that the bytes are in neither memory nor disk, and the retry policy is applied
    /// around it, so a single display can call it more than once.
    ///
    /// - Parameter id: The image id to fetch.
    /// - Returns: The image bytes, in whatever format the backend stores.
    /// - Throws: Any error. On the display path ``ImageLibrary`` rewraps it as
    ///   ``ImageLoadError/transportFailed(reason:)``, keeping the description.
    func fetch(id: String) async throws -> Data

    /// Uploads bytes and returns the id the backend assigned to them.
    ///
    /// - Parameters:
    ///   - data: The image bytes to upload.
    ///   - contentType: The MIME type of those bytes, such as `image/jpeg`.
    /// - Returns: The new image id, which ``fetch(id:)`` can resolve from then on.
    func upload(_ data: Data, contentType: String) async throws -> String

    /// Deletes an image from the backend.
    ///
    /// Only the backend: the cached copies on this device are dropped separately, by
    /// ``ImageLibrary/remove(id:)``.
    ///
    /// - Parameter id: The image id to delete.
    func delete(id: String) async throws
}
