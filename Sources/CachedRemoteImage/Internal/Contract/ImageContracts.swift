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

struct UploadImageContract: APIContract, APIInput {
    typealias Input = Self
    typealias Output = ImageResourceDTO

    static let method: APIMethod = .post
    static let subPath: String = ""

    let basePath: String
    let imageData: Data
    let boundary: String

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    func encodeBody(using encoder: JSONEncoder) throws -> Data? {
        var body = Data()

        // ファイルパート
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
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
