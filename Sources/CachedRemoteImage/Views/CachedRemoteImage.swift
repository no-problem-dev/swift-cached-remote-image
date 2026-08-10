import SwiftUI

/// A view that shows a remote image and handles its placeholder, loading and error states.
///
/// ```swift
/// // Defaults for every state
/// CachedRemoteImage(source: .imageId("abc123"))
///
/// // Every state replaced
/// CachedRemoteImage(source: .imageId("abc123")) { image in
///     image.resizable()
/// } loading: {
///     ProgressView()
/// } error: { _ in
///     Text("Could not load")
/// } placeholder: {
///     Color.gray.opacity(0.2)
/// }
/// ```
///
/// The library comes from the environment, so inject one at the root and every view below it
/// shares the same caches:
///
/// ```swift
/// ContentView()
///     .imageLibrary(library)
/// ```
///
/// Cache and retry settings belong to that library, not to the view — the caches are one shared
/// resource, and a view is not the thing that owns them. Loading starts when the view appears,
/// restarts when the source changes, and stops when the view goes away.
public struct CachedRemoteImage<Content: View, Loading: View, ErrorView: View, Placeholder: View>: View {
    @Environment(\.imageLibrary) private var imageLibrary
    @State private var loader: CachedRemoteImageLoader?

    private let source: ImageSource
    private let contentMode: ContentMode
    private let content: (Image) -> Content
    private let loading: () -> Loading
    private let error: (ImageLoadError) -> ErrorView
    private let placeholder: () -> Placeholder

    /// Creates a view whose every state you supply yourself.
    ///
    /// - Parameters:
    ///   - source: Where the image comes from.
    ///   - contentMode: How the image fits the space it is given. Defaults to `.fit`.
    ///   - content: Builds the view for the loaded image.
    ///   - loading: Builds the view shown while the fetch is in flight.
    ///   - error: Builds the view shown when the load failed, given the reason it failed.
    ///   - placeholder: Builds the view shown before loading starts.
    public init(
        source: ImageSource,
        contentMode: ContentMode = .fit,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder loading: @escaping () -> Loading,
        @ViewBuilder error: @escaping (ImageLoadError) -> ErrorView,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.source = source
        self.contentMode = contentMode
        self.content = content
        self.loading = loading
        self.error = error
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if let loader = loader {
                switch loader.state {
                case .idle:
                    placeholder()
                case .loading:
                    loading()
                case .success(let image):
                    #if canImport(UIKit)
                    content(Image(uiImage: image))
                        .aspectRatio(contentMode: contentMode)
                    #elseif canImport(AppKit)
                    content(Image(nsImage: image))
                        .aspectRatio(contentMode: contentMode)
                    #endif
                case .failure(let loadError):
                    error(loadError)
                }
            } else {
                placeholder()
            }
        }
        .task(id: source) {
            // A missing library is handed to the loader rather than dealt with here.
            // Returning early instead would show nothing and leave the reason nowhere.
            let newLoader = CachedRemoteImageLoader(library: imageLibrary, source: source)
            self.loader = newLoader
            await newLoader.load()
        }
    }
}

// MARK: - Convenience Initializers

extension CachedRemoteImage where Loading == DefaultLoadingView, ErrorView == DefaultErrorView {
    /// Creates a view that customizes the image and the placeholder only.
    ///
    /// The loading and error states use the built-in views.
    ///
    /// - Parameters:
    ///   - source: Where the image comes from.
    ///   - contentMode: How the image fits the space it is given. Defaults to `.fit`.
    ///   - content: Builds the view for the loaded image.
    ///   - placeholder: Builds the view shown before loading starts.
    public init(
        source: ImageSource,
        contentMode: ContentMode = .fit,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            source: source,
            contentMode: contentMode,
            content: content,
            loading: { DefaultLoadingView() },
            error: { DefaultErrorView(error: $0) },
            placeholder: placeholder
        )
    }
}

extension CachedRemoteImage where Loading == DefaultLoadingView, ErrorView == DefaultErrorView, Placeholder == DefaultPlaceholderView {
    /// Creates a view that customizes the loaded image only.
    ///
    /// The loading, error and placeholder states use the built-in views.
    ///
    /// - Parameters:
    ///   - source: Where the image comes from.
    ///   - contentMode: How the image fits the space it is given. Defaults to `.fit`.
    ///   - content: Builds the view for the loaded image.
    public init(
        source: ImageSource,
        contentMode: ContentMode = .fit,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            source: source,
            contentMode: contentMode,
            content: content,
            loading: { DefaultLoadingView() },
            error: { DefaultErrorView(error: $0) },
            placeholder: { DefaultPlaceholderView() }
        )
    }
}

extension CachedRemoteImage where Content == Image, Loading == DefaultLoadingView, ErrorView == DefaultErrorView, Placeholder == DefaultPlaceholderView {
    /// Creates a view that uses the built-in appearance for every state.
    ///
    /// The loaded image is made resizable, so give it a frame or let the layout size it.
    ///
    /// - Parameters:
    ///   - source: Where the image comes from.
    ///   - contentMode: How the image fits the space it is given. Defaults to `.fit`.
    public init(
        source: ImageSource,
        contentMode: ContentMode = .fit
    ) {
        self.init(
            source: source,
            contentMode: contentMode,
            content: { $0.resizable() },
            loading: { DefaultLoadingView() },
            error: { DefaultErrorView(error: $0) },
            placeholder: { DefaultPlaceholderView() }
        )
    }
}

// MARK: - Environment Support

private struct ImageLibraryKey: EnvironmentKey {
    static let defaultValue: ImageLibrary? = nil
}

public extension EnvironmentValues {
    /// The library that image views below this point fetch and cache through.
    ///
    /// `nil` until something injects one, at which point those views fail with
    /// ``ImageLoadError/libraryNotConfigured`` rather than showing nothing.
    var imageLibrary: ImageLibrary? {
        get { self[ImageLibraryKey.self] }
        set { self[ImageLibraryKey.self] = newValue }
    }
}

public extension View {
    /// Makes an image library available to every image view below this one.
    ///
    /// Call it once, at the root. Calling it again further down overrides the library for that
    /// subtree.
    ///
    /// - Parameter library: The library those views fetch and cache through.
    func imageLibrary(_ library: ImageLibrary) -> some View {
        environment(\.imageLibrary, library)
    }
}
