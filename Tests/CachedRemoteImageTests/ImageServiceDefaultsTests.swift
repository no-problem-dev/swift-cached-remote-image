import XCTest
@testable import CachedRemoteImage

// scoped import で DeveloperToolsSupport.ImageResource との型名衝突を回避する
import struct CachedRemoteImage.ImageResource

/// `loadImage(imageId:)` を足したときの互換性と、失敗の伝え方。
///
/// 既定実装が今までと同じ 2 段階（メタデータ取得 → URL ダウンロード）を踏むことを確かめる。
/// ここが崩れると、URL を返せるバックエンドを使っている既存の利用者が黙って画像を出せなくなる。
final class ImageServiceDefaultsTests: XCTestCase {

    private struct MetadataUnavailable: Error {}

    /// URL 経路だけを実装した、要件追加前の利用者に相当するサービス
    private final class URLBackedService: ImageService, @unchecked Sendable {
        var requestedImageIds: [String] = []
        var loadedURLs: [URL] = []
        var resource = ImageResource(id: "img-1", url: URL(string: "https://example.com/img-1.jpg")!)

        func getImageResource(imageId: String) async throws -> ImageResource {
            requestedImageIds.append(imageId)
            return resource
        }

        @MainActor
        func loadImage(from url: URL) async -> PlatformImage? {
            loadedURLs.append(url)
            return PlatformImage()
        }

        func uploadImage(imageData: Data) async throws -> ImageResource { resource }
        func uploadImage(imageData: Data, contentType: String) async throws -> ImageResource { resource }
        func deleteImage(imageId: String) async throws {}
        func clearResourceCache() async {}
        func clearImageCache() async {}
        func diskCacheSize() async -> Int64 { 0 }
    }

    /// メタデータ取得に失敗するサービス
    private final class ThrowingService: ImageService, @unchecked Sendable {
        func getImageResource(imageId: String) async throws -> ImageResource {
            throw MetadataUnavailable()
        }
        @MainActor func loadImage(from url: URL) async -> PlatformImage? { PlatformImage() }
        func uploadImage(imageData: Data) async throws -> ImageResource { throw MetadataUnavailable() }
        func uploadImage(imageData: Data, contentType: String) async throws -> ImageResource {
            throw MetadataUnavailable()
        }
        func deleteImage(imageId: String) async throws {}
        func clearResourceCache() async {}
        func clearImageCache() async {}
        func diskCacheSize() async -> Int64 { 0 }
    }

    /// 公開 URL を持たず、バイト列を直接返すバックエンド
    private final class DirectBytesService: ImageService, @unchecked Sendable {
        var resolvedImageIds: [String] = []

        func getImageResource(imageId: String) async throws -> ImageResource {
            XCTFail("URL を持たないバックエンドでメタデータ経路に落ちてはいけない")
            throw MetadataUnavailable()
        }

        @MainActor func loadImage(from url: URL) async -> PlatformImage? {
            XCTFail("URL 経路に落ちてはいけない")
            return nil
        }

        @MainActor
        func loadImage(imageId: String) async throws -> PlatformImage? {
            resolvedImageIds.append(imageId)
            return PlatformImage()
        }

        func uploadImage(imageData: Data) async throws -> ImageResource { throw MetadataUnavailable() }
        func uploadImage(imageData: Data, contentType: String) async throws -> ImageResource {
            throw MetadataUnavailable()
        }
        func deleteImage(imageId: String) async throws {}
        func clearResourceCache() async {}
        func clearImageCache() async {}
        func diskCacheSize() async -> Int64 { 0 }
    }

    @MainActor
    func testDefaultImplementationGoesThroughResourceURL() async throws {
        let service = URLBackedService()

        let image = try await service.loadImage(imageId: "img-1")

        XCTAssertNotNil(image)
        XCTAssertEqual(service.requestedImageIds, ["img-1"])
        XCTAssertEqual(service.loadedURLs.map(\.absoluteString), ["https://example.com/img-1.jpg"])
    }

    /// 独自実装を持つバックエンドでは、既定実装（URL 経路）を一切通らない
    @MainActor
    func testCustomImplementationBypassesResourceLookup() async throws {
        let service = DirectBytesService()

        let image = try await service.loadImage(imageId: "img-9")

        XCTAssertNotNil(image)
        XCTAssertEqual(service.resolvedImageIds, ["img-9"])
    }

    /// 回帰: メタデータ取得の失敗を握りつぶして `nil` にしてはいけない。
    ///
    /// `try?` で握りつぶすと、呼び出し側は原因を失ったまま「ダウンロード失敗」として扱うことになる。
    /// 実際に取れなかったのはメタデータであって、ダウンロードには到達すらしていない。
    @MainActor
    func testMetadataFailurePropagatesInsteadOfBecomingNil() async {
        do {
            _ = try await ThrowingService().loadImage(imageId: "img-1")
            XCTFail("メタデータ取得の失敗が握りつぶされている")
        } catch is MetadataUnavailable {
            // 期待どおり原因がそのまま届いた
        } catch {
            XCTFail("想定外のエラー: \(error)")
        }
    }
}
