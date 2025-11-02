import SwiftUI

/// リモート画像をキャッシュ付きで表示するビュー
///
/// 使用例:
/// ```swift
/// // シンプル
/// CachedRemoteImage(source: .imageId("abc123"))
///
/// // カスタマイズ
/// CachedRemoteImage(source: .imageId("abc123")) { image in
///     image.resizable()
/// } loading: {
///     ProgressView()
/// }
/// ```
///
/// Environment設定:
/// ```swift
/// ContentView()
///     .environment(\.imageService, imageService)
/// ```
public struct CachedRemoteImage<Content: View, Loading: View, ErrorView: View, Placeholder: View>: View {
    @Environment(\.imageService) private var imageService
    @State private var loader: CachedRemoteImageLoader?

    private let source: ImageSource
    private let contentMode: ContentMode
    private let configuration: CachedRemoteImageConfiguration
    private let content: (Image) -> Content
    private let loading: () -> Loading
    private let error: (ImageLoadError) -> ErrorView
    private let placeholder: () -> Placeholder

    /// カスタムビューを指定可能なイニシャライザ
    public init(
        source: ImageSource,
        contentMode: ContentMode = .fit,
        configuration: CachedRemoteImageConfiguration = .standard,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder loading: @escaping () -> Loading,
        @ViewBuilder error: @escaping (ImageLoadError) -> ErrorView,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.source = source
        self.contentMode = contentMode
        self.configuration = configuration
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
            guard let imageService = imageService else {
                print("⚠️ ImageService not configured. Please inject via .environment(\\.imageService, service)")
                return
            }
            let newLoader = CachedRemoteImageLoader(
                imageService: imageService,
                source: source,
                configuration: configuration
            )
            self.loader = newLoader
            await newLoader.load()
        }
    }
}

// MARK: - Convenience Initializers

extension CachedRemoteImage where Loading == DefaultLoadingView, ErrorView == DefaultErrorView {
    /// デフォルトのローディング・エラービューを使用するイニシャライザ
    ///
    /// ローディングとエラービューはデフォルト実装を使用し、
    /// 画像とプレースホルダーのみカスタマイズできます。
    ///
    /// - Parameters:
    ///   - source: 画像の取得元
    ///   - contentMode: 画像の表示モード（デフォルト: .fit）
    ///   - configuration: キャッシュとリトライの設定（デフォルト: .standard）
    ///   - content: 画像を表示するビルダー
    ///   - placeholder: 読み込み開始前に表示するビュー
    public init(
        source: ImageSource,
        contentMode: ContentMode = .fit,
        configuration: CachedRemoteImageConfiguration = .standard,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            source: source,
            contentMode: contentMode,
            configuration: configuration,
            content: content,
            loading: { DefaultLoadingView() },
            error: { DefaultErrorView(error: $0) },
            placeholder: placeholder
        )
    }
}

extension CachedRemoteImage where Loading == DefaultLoadingView, ErrorView == DefaultErrorView, Placeholder == DefaultPlaceholderView {
    /// 最もシンプルなイニシャライザ（画像のみカスタマイズ）
    ///
    /// ローディング、エラー、プレースホルダーはすべてデフォルト実装を使用します。
    ///
    /// - Parameters:
    ///   - source: 画像の取得元
    ///   - contentMode: 画像の表示モード（デフォルト: .fit）
    ///   - configuration: キャッシュとリトライの設定（デフォルト: .standard）
    ///   - content: 画像を表示するビルダー
    public init(
        source: ImageSource,
        contentMode: ContentMode = .fit,
        configuration: CachedRemoteImageConfiguration = .standard,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(
            source: source,
            contentMode: contentMode,
            configuration: configuration,
            content: content,
            loading: { DefaultLoadingView() },
            error: { DefaultErrorView(error: $0) },
            placeholder: { DefaultPlaceholderView() }
        )
    }
}

extension CachedRemoteImage where Content == Image, Loading == DefaultLoadingView, ErrorView == DefaultErrorView, Placeholder == DefaultPlaceholderView {
    /// 完全にデフォルトのイニシャライザ
    ///
    /// すべてデフォルト実装を使用する、最もシンプルな使い方です。
    ///
    /// - Parameters:
    ///   - source: 画像の取得元
    ///   - contentMode: 画像の表示モード（デフォルト: .fit）
    ///   - configuration: キャッシュとリトライの設定（デフォルト: .standard）
    public init(
        source: ImageSource,
        contentMode: ContentMode = .fit,
        configuration: CachedRemoteImageConfiguration = .standard
    ) {
        self.init(
            source: source,
            contentMode: contentMode,
            configuration: configuration,
            content: { $0.resizable() },
            loading: { DefaultLoadingView() },
            error: { DefaultErrorView(error: $0) },
            placeholder: { DefaultPlaceholderView() }
        )
    }
}

// MARK: - Environment Support

/// ImageService用のEnvironmentKey
public struct ImageServiceKey: EnvironmentKey {
    public static var defaultValue: ImageService? {
        nil
    }
}

public extension EnvironmentValues {
    var imageService: ImageService? {
        get { self[ImageServiceKey.self] }
        set { self[ImageServiceKey.self] = newValue }
    }
}

// MARK: - View Modifier for ImageService Injection

/// ImageServiceを注入するためのViewModifier
/// パッケージ境界を越えて環境値を確実に伝播させるために使用
public struct ImageServiceModifier: ViewModifier {
    private let imageService: ImageService
    
    public init(imageService: ImageService) {
        self.imageService = imageService
    }
    
    public func body(content: Content) -> some View {
        content
            .environment(\.imageService, imageService)
    }
}

public extension View {
    /// ImageServiceを注入する
    /// - Parameter imageService: 使用するImageServiceインスタンス
    /// - Returns: ImageServiceが注入されたView
    func imageService(_ imageService: ImageService) -> some View {
        modifier(ImageServiceModifier(imageService: imageService))
    }
}
