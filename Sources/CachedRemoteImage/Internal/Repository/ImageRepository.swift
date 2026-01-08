import Foundation
import APIClient

/// 画像リソース取得のリポジトリ（内部実装）
///
/// APIClientを使用してREST APIから画像リソース情報を取得
internal struct ImageRepository<Client: APIExecutable>: Sendable {
    let apiClient: Client
    let imagesPath: String

    init(apiClient: Client, imagesPath: String) {
        self.apiClient = apiClient
        self.imagesPath = imagesPath
    }

    /// 画像リソースを取得
    /// - Parameter imageId: 画像ID
    /// - Returns: 画像リソース
    func getImageResource(imageId: String) async throws -> ImageResource {
        let dto: ImageResourceDTO = try await apiClient.execute(
            GetImageResourceContract(basePath: imagesPath, imageId: imageId)
        )
        return dto.toResource()
    }
}
