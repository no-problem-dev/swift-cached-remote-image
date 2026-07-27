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
/// 既定実装は同梱していない。同梱すると、それを使わない利用者の依存解決まで縛るため
/// （SPM の依存解決はパッケージ単位で、使わないターゲットのために宣言した依存も
/// 利用者の解決空間に入る）。メタデータ API が公開 URL を返す形のバックエンドなら、
/// ``fetch(id:)`` の中を「メタデータを引く → その URL からバイト列を取る」の 2 段階にする。
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
