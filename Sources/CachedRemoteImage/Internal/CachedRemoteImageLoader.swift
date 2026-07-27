import Foundation

/// 1 枚の画像の読み込み状態を持つ。
///
/// 再試行は ``ImageLibrary`` 側にある。ビューを経由しない取得（先読みなど）にも
/// 同じ方針が効いている必要があるため。ここがやるのは
/// 「``ImageSource`` を ``ImageLibrary`` の呼び分けに変える」ことと状態の保持だけ。
@MainActor
@Observable
final class CachedRemoteImageLoader {
    private(set) var state: LoadingState = .idle

    /// 環境に ``ImageLibrary`` が無ければ `nil`。
    /// 未注入は失敗として状態に載せる（3.x はここで `print` して素通りしていた）
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
