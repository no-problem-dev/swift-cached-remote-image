import Foundation

/// 画像読み込みロジックを管理するObservableクラス
///
/// ImageServiceを使用して画像を読み込み、状態を管理します。
@MainActor
@Observable
internal final class CachedRemoteImageLoader {
    private(set) var state: LoadingState = .idle

    private let imageService: ImageService
    private let source: ImageSource
    private let configuration: CachedRemoteImageConfiguration

    init(
        imageService: ImageService,
        source: ImageSource,
        configuration: CachedRemoteImageConfiguration
    ) {
        self.imageService = imageService
        self.source = source
        self.configuration = configuration
    }

    func load() async {
        // すでに読み込み済みまたは読み込み中の場合はスキップ
        guard case .idle = state else { return }

        state = .loading(progress: nil)

        // リトライ戦略に基づいて読み込み
        let maxAttempts = configuration.retryPolicy.maxRetries + 1
        var lastError: ImageLoadError?

        for attemptNumber in 0..<maxAttempts {
            // 2回目以降は待機
            if attemptNumber > 0 {
                let delay = await configuration.retryPolicy.delay(for: attemptNumber - 1)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            // 読み込み実行
            do {
                let image = try await loadImage()
                state = .success(image)
                return
            } catch let error as ImageLoadError {
                lastError = error
                // 最後の試行でなければ続行
                if attemptNumber < maxAttempts - 1 {
                    continue
                }
            } catch {
                lastError = .unknown(error.localizedDescription)
                if attemptNumber < maxAttempts - 1 {
                    continue
                }
            }
        }

        // すべての試行が失敗
        state = .failure(lastError ?? .unknown("Unknown error"))
    }

    private func loadImage() async throws -> PlatformImage {
        // URLが直接指定されている場合
        if let url = source.resolvedURL {
            guard let image = await imageService.loadImage(from: url) else {
                throw ImageLoadError.downloadFailed
            }
            return image
        }

        // imageId から取得。URL を返せるバックエンドでは既定実装が
        // メタデータ経由で URL を引くので、従来の 2 段階と同じ動きになる
        guard let imageId = source.imageId else {
            throw ImageLoadError.invalidURL("Invalid image source")
        }

        guard let image = await imageService.loadImage(imageId: imageId) else {
            throw ImageLoadError.downloadFailed
        }

        return image
    }
}
