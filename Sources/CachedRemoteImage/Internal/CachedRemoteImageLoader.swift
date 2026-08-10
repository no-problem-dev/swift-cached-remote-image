import Foundation

/// Holds the loading state of one image for one view.
///
/// Retries live in ``ImageLibrary`` instead, so that fetches which never go through a view —
/// prefetching, for instance — follow the same policy. All this does is turn an ``ImageSource``
/// into the matching library call and keep the resulting state.
@MainActor
@Observable
final class CachedRemoteImageLoader {
    private(set) var state: LoadingState = .idle

    /// `nil` when nothing injected a library into the environment.
    ///
    /// That case is recorded as a failure in the state rather than passed over, so the reason
    /// reaches the error view instead of disappearing.
    private let library: ImageLibrary?
    private let source: ImageSource

    init(library: ImageLibrary?, source: ImageSource) {
        self.library = library
        self.source = source
    }

    func load() async {
        guard case .idle = state else { return }

        guard let library else {
            state = .failure(.libraryNotConfigured)
            return
        }

        state = .loading(progress: nil)

        do {
            state = .success(try await image(from: library))
        } catch let error as ImageLoadError {
            state = .failure(error)
        } catch {
            state = .failure(.transportFailed(reason: error.localizedDescription))
        }
    }

    private func image(from library: ImageLibrary) async throws -> PlatformImage {
        switch source {
        case .imageId(let id):
            return try await library.image(for: id)
        case .url(let url):
            return try await library.image(from: url)
        case .urlString(let string):
            guard let url = URL(string: string) else {
                throw ImageLoadError.invalidURL(string)
            }
            return try await library.image(from: url)
        }
    }
}
