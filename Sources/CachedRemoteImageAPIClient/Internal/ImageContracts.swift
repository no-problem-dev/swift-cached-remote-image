import APIClient
import Foundation

// MARK: - Get Image Resource

struct GetImageResourceContract: APIContract, APIInput {
    typealias Input = Self
    typealias Output = ImageResourceDTO

    static let method: APIMethod = .get
    static let subPath: String = ""

    let basePath: String
    let imageId: String

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }

    static func resolvePath(with input: Self) -> String {
        "\(input.basePath)/\(input.imageId)"
    }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: any APIBodyDecoder
    ) throws -> Self {
        fatalError("Client-only contract")
    }
}

// MARK: - Upload Image

/// 画像アップロード（`multipart/form-data`）
///
/// 境界文字列はインスタンスが持つ。ヘッダーとボディで同じ値を使う必要があり、
/// それぞれが別々に生成すると食い違うため
struct UploadImageContract: APIContract, APIInput {
    typealias Input = Self
    typealias Output = ImageResourceDTO

    static let method: APIMethod = .post
    static let subPath: String = ""

    let basePath: String
    let imageData: Data
    let contentType: String
    let fieldName: String
    let boundary: String

    init(
        basePath: String,
        imageData: Data,
        contentType: String,
        fieldName: String,
        boundary: String = MultipartFormData().boundary
    ) {
        self.basePath = basePath
        self.imageData = imageData
        self.contentType = contentType
        self.fieldName = fieldName
        self.boundary = boundary
    }

    private var form: MultipartFormData { MultipartFormData(boundary: boundary) }

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    /// ボディがあると APIClient は既定で `application/json` を付ける。
    /// エンドポイント固有ヘッダーはそれより後に適用されるので、ここで上書きできる
    var additionalHeaders: [String: String] {
        ["Content-Type": form.contentTypeHeaderValue]
    }

    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? {
        form.body(
            fieldName: fieldName,
            fileName: MultipartFormData.fileName(for: contentType),
            contentType: contentType,
            data: imageData
        )
    }

    static func resolvePath(with input: Self) -> String {
        input.basePath
    }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: any APIBodyDecoder
    ) throws -> Self {
        fatalError("Client-only contract")
    }
}

// MARK: - Delete Image

struct DeleteImageContract: APIContract, APIInput {
    typealias Input = Self
    typealias Output = EmptyOutput

    static let method: APIMethod = .delete
    static let subPath: String = ""

    let basePath: String
    let imageId: String

    var pathParameters: [String: String] { [:] }
    var queryParameters: [String: String]? { nil }

    func encodeBody(using encoder: any APIBodyEncoder) throws -> Data? { nil }

    static func resolvePath(with input: Self) -> String {
        "\(input.basePath)/\(input.imageId)"
    }

    static func decode(
        pathParameters: [String: String],
        queryParameters: [String: String],
        body: Data?,
        decoder: any APIBodyDecoder
    ) throws -> Self {
        fatalError("Client-only contract")
    }
}
