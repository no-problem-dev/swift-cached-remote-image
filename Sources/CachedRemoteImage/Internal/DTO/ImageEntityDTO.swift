import Foundation
import GeneralDomain

/// 画像エンティティのDTO（RESTful API標準構造）
internal struct ImageEntityDTO: Codable {
    let id: String
    let url: String
    let contentType: String
    let size: Int
    let metadata: MetadataDTO?
    let createdAt: String  // ISO 8601
    let updatedAt: String  // ISO 8601

    struct MetadataDTO: Codable {
        let width: Int?
        let height: Int?
    }

    func toDomain() -> ImageEntity {
        let domainMetadata = metadata.map { dto in
            ImageEntity.ImageMetadata(width: dto.width, height: dto.height)
        }

        let dateFormatter = ISO8601DateFormatter()

        return ImageEntity(
            id: id,
            url: url,
            contentType: contentType,
            size: size,
            metadata: domainMetadata,
            createdAt: dateFormatter.date(from: createdAt) ?? Date(),
            updatedAt: dateFormatter.date(from: updatedAt) ?? Date()
        )
    }
}
