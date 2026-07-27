import APIClient
import CachedRemoteImage
import Foundation

/// 公開 URL を返すバックエンド向けの ``ImageTransport``。
///
/// `GET /images/{id}` が `{ "id": ..., "url": ... }` を返し、その URL から
/// 画像バイト列を取れる形の API — 3.x が唯一サポートしていた形 — をそのまま扱う。
/// 既存の利用者はこれを渡せば従来と同じ経路で動く。
///
/// ID → URL の 1 往復は内部で LRU キャッシュする。バイト列のキャッシュはここではなく
/// ``ImageLibrary`` にある（どんな transport でも同じように効かせるため）。
///
/// ## 使い方
/// ```swift
/// let transport = URLImageTransport(
///     apiClient: apiClient,
///     imagesPath: "/v1/images"
/// )
/// let library = try ImageLibrary(transport: transport)
/// ```
///
/// ## 必要な API
/// - `GET {imagesPath}/{id}` → `{ "id": "...", "url": "https://..." }`
/// - `POST {imagesPath}` → `multipart/form-data` を受けて同じ形を返す
/// - `DELETE {imagesPath}/{id}`
public struct URLImageTransport<Client: APIExecutable>: ImageTransport {
    private let apiClient: Client
    private let imagesPath: String
    private let uploadFieldName: String
    private let urlSession: URLSession
    private let urlCache: ImageURLCache

    /// - Parameters:
    ///   - apiClient: メタデータ API を叩くクライアント
    ///   - imagesPath: 画像 API のパス（baseURL からの相対）
    ///   - uploadFieldName: multipart のフィールド名。サーバーが読む名前に合わせる
    ///   - maxURLCacheSize: ID → URL キャッシュの上限件数
    ///   - urlSession: 画像バイト列のダウンロードに使うセッション
    public init(
        apiClient: Client,
        imagesPath: String,
        uploadFieldName: String = "file",
        maxURLCacheSize: Int = 100,
        urlSession: URLSession = .shared
    ) {
        self.apiClient = apiClient
        self.imagesPath = imagesPath
        self.uploadFieldName = uploadFieldName
        self.urlSession = urlSession
        self.urlCache = ImageURLCache(maxCacheSize: maxURLCacheSize)
    }

    public func fetch(id: String) async throws -> Data {
        let url = try await resolveURL(for: id)
        let (data, response) = try await urlSession.data(from: url)

        // 404 の HTML を画像として復号しようとして「画像ではない」と報告するより、
        // 取得の失敗として扱ったほうが原因に近い
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLImageTransportError.unexpectedStatus(code: http.statusCode, url: url)
        }
        return data
    }

    public func upload(_ data: Data, contentType: String) async throws -> String {
        let dto: ImageResourceDTO = try await apiClient.execute(
            UploadImageContract(
                basePath: imagesPath,
                imageData: data,
                contentType: contentType,
                fieldName: uploadFieldName
            )
        )
        // 上げた直後に表示することが多いので、URL 解決の 1 往復を先に埋めておく
        await urlCache.set(try dto.resolvedURL(), for: dto.id)
        return dto.id
    }

    public func delete(id: String) async throws {
        try await apiClient.execute(
            DeleteImageContract(basePath: imagesPath, imageId: id)
        )
        await urlCache.remove(for: id)
    }

    private func resolveURL(for id: String) async throws -> URL {
        if let cached = await urlCache.url(for: id) {
            return cached
        }
        let dto: ImageResourceDTO = try await apiClient.execute(
            GetImageResourceContract(basePath: imagesPath, imageId: id)
        )
        let url = try dto.resolvedURL()
        await urlCache.set(url, for: id)
        return url
    }
}

/// ``URLImageTransport`` が失敗した原因
public enum URLImageTransportError: Error, Equatable, Sendable {
    /// メタデータ API が URL として解釈できない値を返した
    case malformedResourceURL(id: String, url: String)
    /// 画像 URL が 2xx 以外を返した
    case unexpectedStatus(code: Int, url: URL)
}

extension URLImageTransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .malformedResourceURL(let id, let url):
            return "画像 \(id) の URL を解釈できない: \(url)"
        case .unexpectedStatus(let code, let url):
            return "画像の取得が HTTP \(code): \(url)"
        }
    }
}
