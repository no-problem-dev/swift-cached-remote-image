import Foundation
import APIClient

// MARK: - Get Image Resource Contract

struct GetImageResourceContract: APIContract, APIInput {
    typealias Input = Self
    typealias Output = ImageResourceDTO

    static let method: APIMethod = .get
    static let subPath: String = ""

    let basePath: String
    let imageId: String

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    func encodeBody(using encoder: JSONEncoder) throws -> Data? { nil }

    static func resolvePath(with input: Self) -> String {
        "\(input.basePath)/\(input.imageId)"
    }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: JSONDecoder
    ) throws -> Self {
        fatalError("Client-only contract")
    }
}

// MARK: - Upload Image Contract

/// アップロードリクエストボディ（Base64エンコード）
struct UploadImageRequestBody: Codable {
    let imageData: String
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case imageData = "image_data"
        case contentType = "content_type"
    }
}

struct UploadImageContract: APIContract, APIInput {
    typealias Input = Self
    typealias Output = ImageResourceDTO

    static let method: APIMethod = .post
    static let subPath: String = ""

    let basePath: String
    let imageData: Data
    let contentType: String

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    func encodeBody(using encoder: JSONEncoder) throws -> Data? {
        // Base64エンコードしてJSON形式で送信
        let base64String = imageData.base64EncodedString()
        let requestBody = UploadImageRequestBody(
            imageData: base64String,
            contentType: contentType
        )
        return try encoder.encode(requestBody)
    }

    static func resolvePath(with input: Self) -> String {
        input.basePath
    }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: JSONDecoder
    ) throws -> Self {
        fatalError("Client-only contract")
    }
}

// MARK: - Delete Image Contract

struct DeleteImageContract: APIContract, APIInput {
    typealias Input = Self
    typealias Output = EmptyOutput

    static let method: APIMethod = .delete
    static let subPath: String = ""

    let basePath: String
    let imageId: String

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    func encodeBody(using encoder: JSONEncoder) throws -> Data? { nil }

    static func resolvePath(with input: Self) -> String {
        "\(input.basePath)/\(input.imageId)"
    }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: JSONDecoder
    ) throws -> Self {
        fatalError("Client-only contract")
    }
}
