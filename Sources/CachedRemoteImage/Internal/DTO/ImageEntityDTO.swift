import Foundation

/// 画像リソースのDTO（最小限の構造）
internal struct ImageResourceDTO: Codable {
    let id: String
    let url: String

    func toResource() -> ImageResource {
        guard let url = URL(string: url) else {
            fatalError("Invalid URL: \(url)")
        }

        return ImageResource(
            id: id,
            url: url
        )
    }
}
