import CryptoKit
import Foundation

/// キャッシュのキー。
///
/// 画像 ID と URL は同じディレクトリ・同じ NSCache に同居するので、
/// 名前空間を分けておかないと「`https://…` という ID」のような値が衝突しうる。
/// 衝突すると別の画像が出るという最悪の壊れ方をするので、型で分ける。
enum ImageCacheKey: Hashable, Sendable {
    case id(String)
    case url(String)

    /// 名前空間つきの文字列表現
    private var namespaced: String {
        switch self {
        case .id(let id): return "id:\(id)"
        case .url(let url): return "url:\(url)"
        }
    }

    /// メモリキャッシュ（NSCache）のキー
    var memoryKey: NSString {
        namespaced as NSString
    }

    /// ディスク上のファイル名。
    ///
    /// ID や URL をそのままファイル名にすると、長さ上限（255 バイト）と
    /// パス区切り文字の両方に引っかかる。中身ではなくキーのハッシュを名前にすることで、
    /// キーの形に関係なく固定長で安全な名前になる。
    var fileName: String {
        let digest = SHA256.hash(data: Data(namespaced.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
