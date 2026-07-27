import Foundation

/// 画像バイト列の出し入れ。
///
/// 認証・エンドポイント・レスポンス形式はアプリごとに違い、パッケージが当てられる場所ではない。
/// 3.x まではパッケージが「メタデータ API で URL を引いて URLSession で取る」という取り方を
/// 決め打ちしていたが、実際の利用者は非公開ストレージ（認証付きでバイト列を直接返す API）で、
/// 公開 URL が存在しなかった。決め打ちの取り方から外れた利用者は、キャッシュも含めて
/// 全部を自分で書き直すことになっていた。
///
/// そこで責務の向きを逆にした — **取り方はアプリが与え、キャッシュはパッケージが持つ**。
/// アプリが実装するのはこの 3 メソッドだけで、2 層キャッシュ・リトライ・SwiftUI ビューは
/// ``ImageLibrary`` が引き受ける。
///
/// URL を返せるバックエンド向けには `CachedRemoteImageAPIClient` モジュールの
/// `URLImageTransport` を同梱しているので、従来型の API を使っているなら自前実装は要らない。
///
/// ## 実装例
/// ```swift
/// struct MyImageTransport: ImageTransport {
///     let api: MyAPIClient
///
///     func fetch(id: String) async throws -> Data {
///         try await api.getImage(id: id)
///     }
///
///     func upload(_ data: Data, contentType: String) async throws -> String {
///         try await api.uploadImage(data, contentType: contentType).id
///     }
///
///     func delete(id: String) async throws {
///         try await api.deleteImage(id: id)
///     }
/// }
/// ```
public protocol ImageTransport: Sendable {
    /// 画像 ID からバイト列を取得する。
    ///
    /// キャッシュはこの外側（``ImageLibrary``）にあるので、実装はキャッシュを持たなくてよい。
    /// 呼ばれた時点でメモリにもディスクにも無いことが確定している。
    ///
    /// - Parameter id: 画像 ID
    /// - Returns: 画像のバイト列（エンコード形式は問わない）
    /// - Throws: 取得できなかった原因。``ImageLibrary`` は表示のために
    ///   ``ImageLoadError/transportFailed(reason:)`` に包み直すが、原因の説明文は保たれる
    func fetch(id: String) async throws -> Data

    /// バイト列をアップロードして画像 ID を得る。
    ///
    /// - Parameters:
    ///   - data: 画像のバイト列
    ///   - contentType: MIME タイプ（`image/jpeg` など）
    /// - Returns: 採番された画像 ID。以降 ``fetch(id:)`` で引ける値
    func upload(_ data: Data, contentType: String) async throws -> String

    /// 画像を削除する。
    ///
    /// - Parameter id: 画像 ID
    func delete(id: String) async throws
}
