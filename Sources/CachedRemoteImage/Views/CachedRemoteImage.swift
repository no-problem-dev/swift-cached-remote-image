import SwiftUI

/// リモート画像をキャッシュ付きで表示するビュー
///
/// 使用例:
/// ```swift
/// // シンプル
/// CachedRemoteImage(source: .imageId("abc123"))
///
/// // カスタマイズ（全クロージャ指定）
/// CachedRemoteImage(source: .imageId("abc123")) { image in
///     image.resizable()
/// } loading: {
///     ProgressView()
/// } error: { _ in
///     Text("エラー")
/// } placeholder: {
///     Color.gray.opacity(0.2)
/// }
/// ```
///
/// 環境設定（ルートビューで一度だけ）:
/// ```swift
/// ContentView()
///     .imageLibrary(library)
/// ```
///
/// キャッシュと再試行の設定は ``ImageLibrary`` を作るときに決める。
/// ビューごとには渡さない — キャッシュはライブラリが一つ持つ資源で、
/// ビュー単位で切り替えられる性質のものではないため。
public struct CachedRemoteImage<Content: View, Loading: View, ErrorView: View, Placeholder: View>: View {
    @Environment(\.imageLibrary) private var imageLibrary
    @State private var loader: CachedRemoteImageLoader?

    private let source: ImageSource
    private let contentMode: ContentMode
    private let content: (Image) -> Content
    private let loading: () -> Loading
    private let error: (ImageLoadError) -> ErrorView
    private let placeholder: () -> Placeholder

    /// カスタムビューを指定可能なイニシャライザ
    ///
    /// - Parameters:
    ///   - source: 画像の取得元
    ///   - contentMode: 画像の表示モード（デフォルト: .fit）
    ///   - content: 読み込み成功時に画像を表示するビルダー
    ///   - loading: 読み込み中に表示するビルダー
    ///   - error: エラー発生時に表示するビルダー
    ///   - placeholder: 読み込み開始前に表示するビルダー
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
            // ライブラリ未注入もローダーに渡す。ここで握って return すると
            // 「何も出ないが理由はどこにも無い」状態になる
            let newLoader = CachedRemoteImageLoader(library: imageLibrary, source: source)
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
    /// 画像とプレースホルダーのみカスタマイズできる。
    ///
    /// - Parameters:
    ///   - source: 画像の取得元
    ///   - contentMode: 画像の表示モード（デフォルト: .fit）
    ///   - content: 画像を表示するビルダー
    ///   - placeholder: 読み込み開始前に表示するビュー
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
    /// 最もシンプルなイニシャライザ（画像のみカスタマイズ）
    ///
    /// ローディング、エラー、プレースホルダーはすべてデフォルト実装を使用する。
    ///
    /// - Parameters:
    ///   - source: 画像の取得元
    ///   - contentMode: 画像の表示モード（デフォルト: .fit）
    ///   - content: 画像を表示するビルダー
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
    /// 完全にデフォルトのイニシャライザ
    ///
    /// すべてデフォルト実装を使用する最もシンプルな形。
    ///
    /// - Parameters:
    ///   - source: 画像の取得元
    ///   - contentMode: 画像の表示モード（デフォルト: .fit）
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
    /// 画像ライブラリの環境値。`View.imageLibrary(_:)` モディファイアで注入する。
    var imageLibrary: ImageLibrary? {
        get { self[ImageLibraryKey.self] }
        set { self[ImageLibraryKey.self] = newValue }
    }
}

public extension View {
    /// ``ImageLibrary`` を注入する。ルートビューで一度だけ呼ぶ
    ///
    /// - Parameter library: 使用する ``ImageLibrary``
    func imageLibrary(_ library: ImageLibrary) -> some View {
        environment(\.imageLibrary, library)
    }
}
