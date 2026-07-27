import Foundation

/// メタデータ API が返す画像リソース（`{ "id": ..., "url": ... }`）
struct ImageResourceDTO: Codable, Sendable, Equatable {
    let id: String
    let url: String

    /// URL として解釈する。
    ///
    /// 3.x はここで `fatalError` していた。サーバーが壊れた値を返しただけでアプリが落ちる。
    /// 相手の都合で決まる値なので、エラーとして扱う
    func resolvedURL() throws -> URL {
        guard let resolved = URL(string: url) else {
            throw URLImageTransportError.malformedResourceURL(id: id, url: url)
        }
        return resolved
    }
}
