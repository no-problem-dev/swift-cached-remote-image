import XCTest
@testable import CachedRemoteImage
// SwiftUI（XCTest 経由で入る）にも同名のアセット型があるので、
// このファイルではパッケージの ImageResource を名指しで取り込む
import struct CachedRemoteImage.ImageResource

/// `loadImage(imageId:)` を足したときの互換性。
///
/// 既定実装が今までと同じ 2 段階（メタデータ取得 → URL ダウンロード）を踏むことを
/// 確かめる。ここが崩れると、URL を返せるバックエンドを使っている既存の利用者が
/// 黙って画像を出せなくなる。
final class ImageServiceDefaultsTests: XCTestCase {

    /// URL 経路だけを実装した、更新前の利用者に相当するサービス
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
        func getCacheSize() async -> Int64 { 0 }
    }

    private struct MetadataUnavailable: Error {}

    /// メタデータ取得に失敗する、更新前の利用者に相当するサービス
    private final class ThrowingService: ImageService, @unchecked Sendable {
        func getImageResource(imageId: String) async throws -> ImageResource {
            throw MetadataUnavailable()
        }
        @MainActor func loadImage(from url: URL) async -> PlatformImage? { PlatformImage() }
        func uploadImage(imageData: Data) async throws -> ImageResource {
            throw MetadataUnavailable()
        }
        func uploadImage(imageData: Data, contentType: String) async throws -> ImageResource {
            throw MetadataUnavailable()
        }
        func deleteImage(imageId: String) async throws {}
        func clearResourceCache() async {}
        func clearImageCache() async {}
        func getCacheSize() async -> Int64 { 0 }
    }

    @MainActor
    func testDefaultImplementationGoesThroughResourceURL() async {
        let service = URLBackedService()

        let image = await service.loadImage(imageId: "img-1")

        XCTAssertNotNil(image)
        XCTAssertEqual(service.requestedImageIds, ["img-1"])
        XCTAssertEqual(service.loadedURLs.map(\.absoluteString), ["https://example.com/img-1.jpg"])
    }

    /// メタデータが取れなければ nil。呼び出し側はここで失敗を判断する
    @MainActor
    func testDefaultImplementationReturnsNilWhenResourceUnavailable() async {
        let image = await ThrowingService().loadImage(imageId: "img-1")
        XCTAssertNil(image)
    }
}
