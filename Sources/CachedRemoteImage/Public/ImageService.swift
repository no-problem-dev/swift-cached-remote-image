import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(UIKit)
/// iOS/macOS 両対応のプラットフォーム画像型。iOS では `UIImage`、macOS では `NSImage` が割り当てられる。
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
/// iOS/macOS 両対応のプラットフォーム画像型。iOS では `UIImage`、macOS では `NSImage` が割り当てられる。
public typealias PlatformImage = NSImage
#endif

/// 画像管理サービスのプロトコル
///
/// リモート画像のCRUD操作とキャッシュ機能を提供する。
///
/// 使用例:
/// ```swift
/// let service = ImageServiceImpl(
///     apiClient: client,
///     imagesPath: "/images",
///     maxResourceCacheSize: 100
/// )
/// let resource = try await service.uploadImage(imageData: jpegData)
/// let image = await service.loadImage(from: resource.url)
/// ```
public protocol ImageService: Sendable {
    /// 画像リソースを取得（キャッシュ対応）
    ///
    /// - Parameter imageId: 画像ID
    /// - Returns: 画像リソース
    /// - Throws: ネットワークエラー、デコードエラー
    func getImageResource(imageId: String) async throws -> ImageResource

    /// URLから画像を読み込み（メモリ＋ディスクキャッシュ対応）
    ///
    /// - Parameter url: 画像URL
    /// - Returns: プラットフォーム画像（失敗時はnil）
    /// - Note: MainActorで実行されます（PlatformImageは非Sendableのため）
    @MainActor
    func loadImage(from url: URL) async -> PlatformImage?

    /// 画像IDから画像を読み込み（メモリ＋ディスクキャッシュ対応）
    ///
    /// 公開 URL を持たないバックエンド（非公開ストレージ・認証付きで画像バイト列を返す API）
    /// 向けの経路。メタデータに URL が無い場合、`getImageResource` → `loadImage(from:)` の
    /// 2 段階は成立しないため、この要件を実装して直接バイト列を取りに行く。
    ///
    /// 既定実装は従来どおり `getImageResource` で URL を引いて `loadImage(from:)` に委ねるので、
    /// URL を返せるバックエンドの実装者は何もしなくてよい。
    ///
    /// - Parameter imageId: 画像ID
    /// - Returns: プラットフォーム画像（読み込めなかった場合は nil）
    /// - Throws: 画像を特定できなかった原因（メタデータ取得の失敗など）。
    ///   `nil` は「取得はできたが画像にならなかった」を意味し、失敗の原因は throw で伝える
    /// - Note: MainActorで実行されます（PlatformImageは非Sendableのため）
    @MainActor
    func loadImage(imageId: String) async throws -> PlatformImage?

    /// 画像をアップロード
    ///
    /// - Parameter imageData: 画像データ（JPEG推奨）
    /// - Returns: アップロードされた画像リソース
    /// - Throws: ネットワークエラー、サーバーエラー
    func uploadImage(imageData: Data) async throws -> ImageResource

    /// 画像をアップロード（コンテンツタイプ指定）
    ///
    /// - Parameters:
    ///   - imageData: 画像データ
    ///   - contentType: 画像のコンテンツタイプ（image/jpeg, image/png など）
    /// - Returns: アップロードされた画像リソース
    /// - Throws: ネットワークエラー、サーバーエラー
    func uploadImage(imageData: Data, contentType: String) async throws -> ImageResource

    /// 画像を削除
    ///
    /// - Parameter imageId: 画像ID
    /// - Throws: ネットワークエラー、サーバーエラー
    func deleteImage(imageId: String) async throws

    /// リソースキャッシュをクリア
    func clearResourceCache() async

    /// 画像データキャッシュをクリア
    func clearImageCache() async

    /// ディスクキャッシュサイズを取得（バイト単位）
    func diskCacheSize() async -> Int64
}

extension ImageService {
    /// URL を返せるバックエンド向けの既定実装（メタデータ取得 → URL ダウンロード）。
    ///
    /// `getImageResource` の失敗はここで握りつぶさず、そのまま伝播させる。
    /// 握りつぶして `nil` にすると、呼び出し側は原因が分からないまま
    /// 「ダウンロード失敗」として扱うことになる。
    @MainActor
    public func loadImage(imageId: String) async throws -> PlatformImage? {
        let resource = try await getImageResource(imageId: imageId)
        return await loadImage(from: resource.url)
    }
}
