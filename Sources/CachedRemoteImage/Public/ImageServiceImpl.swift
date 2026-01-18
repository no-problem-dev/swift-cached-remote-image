import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import APIClient

/// ImageServiceの実装
///
/// APIClient、リソースキャッシュ、画像データキャッシュを内部で管理し、
/// 効率的な画像のCRUD操作とキャッシュ管理を提供します。
///
/// ## 初期化例
/// ```swift
/// let apiClient = APIClientImpl(baseURL: URL(string: "https://api.example.com")!, ...)
/// let service = ImageServiceImpl(
///     apiClient: apiClient,
///     imagesPath: "/v1/images",
///     maxResourceCacheSize: 200
/// )
/// ```
public struct ImageServiceImpl<Client: APIExecutable>: ImageService {
    private let apiClient: Client
    private let imagesPath: String
    private let repository: ImageRepository<Client>
    private let resourceCache: ImageMetadataCache
    private let imageCache: ImageDataCache

    /// APIClientを使用した初期化
    ///
    /// - Parameters:
    ///   - apiClient: APIクライアント
    ///   - imagesPath: 画像APIのパス（baseURLからの相対パス）
    ///   - maxResourceCacheSize: リソースキャッシュの最大サイズ
    public init(
        apiClient: Client,
        imagesPath: String,
        maxResourceCacheSize: Int
    ) {
        self.apiClient = apiClient
        self.imagesPath = imagesPath
        self.repository = ImageRepository(
            apiClient: apiClient,
            imagesPath: imagesPath
        )
        self.resourceCache = ImageMetadataCache(maxCacheSize: maxResourceCacheSize)
        self.imageCache = ImageDataCache()
    }

    // MARK: - 読み取り操作

    public func getImageResource(imageId: String) async throws -> ImageResource {
        // 1. キャッシュチェック
        if let cached = await resourceCache.get(for: imageId) {
            return cached
        }

        // 2. APIから取得
        let resource = try await repository.getImageResource(imageId: imageId)

        // 3. キャッシュに保存
        await resourceCache.set(resource, for: imageId)

        return resource
    }

    @MainActor
    public func loadImage(from url: URL) async -> PlatformImage? {
        let urlString = url.absoluteString

        // 1. キャッシュチェック（メモリ＋ディスク）
        if let cached = await imageCache.get(for: urlString) {
            return cached
        }

        // 2. URLからダウンロード
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = PlatformImage(data: data) else {
                print("❌ [CachedRemoteImage] Failed to create image from data: \(url)")
                return nil
            }

            // 3. キャッシュに保存
            await imageCache.set(image, for: urlString)

            return image
        } catch {
            print("❌ [CachedRemoteImage] Failed to load image from URL: \(url), error: \(error)")
            return nil
        }
    }

    // MARK: - 書き込み操作

    public func uploadImage(imageData: Data) async throws -> ImageResource {
        try await uploadImage(imageData: imageData, contentType: "image/jpeg")
    }

    public func uploadImage(imageData: Data, contentType: String) async throws -> ImageResource {
        // Base64エンコードしてJSONボディとしてアップロード
        let dto: ImageResourceDTO = try await apiClient.execute(
            UploadImageContract(basePath: imagesPath, imageData: imageData, contentType: contentType)
        )
        let resource = dto.toResource()

        // リソースをキャッシュに保存
        await resourceCache.set(resource, for: resource.id)

        return resource
    }

    public func deleteImage(imageId: String) async throws {
        try await apiClient.execute(
            DeleteImageContract(basePath: imagesPath, imageId: imageId)
        )

        // キャッシュからも削除
        await resourceCache.remove(for: imageId)
    }

    // MARK: - キャッシュ管理

    public func clearResourceCache() async {
        await resourceCache.clearAll()
    }

    public func clearImageCache() async {
        await imageCache.clearAll()
    }

    public func getCacheSize() async -> Int64 {
        await imageCache.getCacheSize()
    }
}
