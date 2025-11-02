import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import GeneralDomain

#if canImport(UIKit)
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
public typealias PlatformImage = NSImage
#endif

/// 画像管理サービスのプロトコル
///
/// リモート画像のCRUD操作とキャッシュ機能を提供します。
///
/// 使用例:
/// ```swift
/// let service = ImageServiceImpl(apiClient: client, imagesPath: "/images")
/// let entity = try await service.uploadImage(imageData: jpegData)
/// let image = await service.loadImage(from: URL(string: entity.url)!)
/// ```
public protocol ImageService: Sendable {
    /// 画像メタデータを取得（キャッシュ対応）
    ///
    /// - Parameter imageId: 画像ID
    /// - Returns: 画像エンティティ
    /// - Throws: ネットワークエラー、デコードエラー
    func getImageMetadata(imageId: String) async throws -> ImageEntity

    /// URLから画像を読み込み（メモリ＋ディスクキャッシュ対応）
    ///
    /// - Parameter url: 画像URL
    /// - Returns: プラットフォーム画像（失敗時はnil）
    func loadImage(from url: URL) async -> PlatformImage?

    /// 画像をアップロード
    ///
    /// - Parameter imageData: 画像データ（JPEG推奨）
    /// - Returns: アップロードされた画像エンティティ
    /// - Throws: ネットワークエラー、サーバーエラー
    func uploadImage(imageData: Data) async throws -> ImageEntity

    /// 画像を削除
    ///
    /// - Parameter imageId: 画像ID
    /// - Throws: ネットワークエラー、サーバーエラー
    func deleteImage(imageId: String) async throws

    /// メタデータキャッシュをクリア
    func clearMetadataCache() async

    /// 画像データキャッシュをクリア
    func clearImageCache() async

    /// ディスクキャッシュサイズを取得（バイト単位）
    func getCacheSize() async -> Int64
}
