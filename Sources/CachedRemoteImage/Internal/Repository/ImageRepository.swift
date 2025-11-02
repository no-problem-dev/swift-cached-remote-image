import Foundation
import APIClient
import GeneralDomain

/// 画像メタデータ取得のリポジトリ（内部実装）
///
/// APIClientを使用してREST APIから画像メタデータを取得
internal struct ImageRepository: Sendable {
    let apiClient: APIClient
    let imagesPath: String

    init(apiClient: APIClient, imagesPath: String) {
        self.apiClient = apiClient
        self.imagesPath = imagesPath
    }

    /// 画像メタデータを取得
    /// - Parameter imageId: 画像ID
    /// - Returns: 画像エンティティ
    func getImageMetadata(imageId: String) async throws -> ImageEntity {
        let endpoint = APIEndpoint(
            path: "\(imagesPath)/\(imageId)",
            method: .get
        )
        let dto: ImageEntityDTO = try await apiClient.request(endpoint)
        return dto.toDomain()
    }
}
