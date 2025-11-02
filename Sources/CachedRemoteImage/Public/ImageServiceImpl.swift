import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import APIClient
import GeneralDomain

/// ImageServiceの実装
///
/// APIClient、メタデータキャッシュ、画像データキャッシュを内部で管理し、
/// 効率的な画像のCRUD操作とキャッシュ管理を提供します。
///
/// ## 初期化例
/// ```swift
/// let apiClient = APIClientImpl(baseURL: URL(string: "https://api.example.com")!, ...)
/// let service = ImageServiceImpl(
///     apiClient: apiClient,
///     imagesPath: "/v1/images",
///     maxMetadataCacheSize: 200
/// )
/// ```
public struct ImageServiceImpl: ImageService {
    private let apiClient: APIClient
    private let imagesPath: String
    private let repository: ImageRepository
    private let metadataCache: ImageMetadataCache
    private let imageCache: ImageDataCache

    /// APIClientを使用した初期化
    ///
    /// - Parameters:
    ///   - apiClient: APIクライアント
    ///   - imagesPath: 画像APIのパス（baseURLからの相対パス）
    ///   - maxMetadataCacheSize: メタデータキャッシュの最大サイズ
    public init(
        apiClient: APIClient,
        imagesPath: String,
        maxMetadataCacheSize: Int
    ) {
        self.apiClient = apiClient
        self.imagesPath = imagesPath
        self.repository = ImageRepository(
            apiClient: apiClient,
            imagesPath: imagesPath
        )
        self.metadataCache = ImageMetadataCache(maxCacheSize: maxMetadataCacheSize)
        self.imageCache = ImageDataCache()
    }

    // MARK: - 読み取り操作

    public func getImageMetadata(imageId: String) async throws -> ImageEntity {
        // 1. キャッシュチェック
        if let cached = await metadataCache.get(for: imageId) {
            return cached
        }

        // 2. APIから取得
        let entity = try await repository.getImageMetadata(imageId: imageId)

        // 3. キャッシュに保存
        await metadataCache.set(entity, for: imageId)

        return entity
    }

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

    public func uploadImage(imageData: Data) async throws -> ImageEntity {
        // マルチパートフォームデータとしてアップロード
        let boundary = UUID().uuidString
        var body = Data()

        // ファイルパート
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let endpoint = APIEndpoint(
            path: imagesPath,
            method: .post,
            headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
            body: body
        )

        // APIは完全なImageEntityを返すようになった
        let dto: ImageEntityDTO = try await apiClient.request(endpoint)
        let entity = dto.toDomain()

        // メタデータをキャッシュに保存
        await metadataCache.set(entity, for: entity.id)

        return entity
    }

    public func deleteImage(imageId: String) async throws {
        let endpoint = APIEndpoint(
            path: "\(imagesPath)/\(imageId)",
            method: .delete
        )
        try await apiClient.request(endpoint)

        // キャッシュからも削除
        await metadataCache.remove(for: imageId)
    }

    // MARK: - キャッシュ管理

    public func clearMetadataCache() async {
        await metadataCache.clearAll()
    }

    public func clearImageCache() async {
        await imageCache.clearAll()
    }

    public func getCacheSize() async -> Int64 {
        await imageCache.getCacheSize()
    }
}
