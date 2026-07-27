import Foundation
import XCTest
@testable import CachedRemoteImage
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - 画像バイト列

enum TestImage {
    /// 実際に復号できる PNG を作る。
    /// 「画像として成立するバイト列」を固定文字列で埋め込むと、
    /// それが本当に画像なのかがテストの外の事実になるので、その場で作る
    static func pngData(width: Int = 4, height: Int = 4) -> Data {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        #elseif canImport(AppKit)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
        #endif
    }

    /// 画像として復号できないバイト列
    static let notAnImage = Data("this is not an image".utf8)
}

// MARK: - ImageTransport のテストダブル

/// 呼ばれ方を記録し、応答をスクリプトできる ``ImageTransport``。ネットワークには一切出ない。
final class FakeImageTransport: ImageTransport, @unchecked Sendable {
    enum Behavior {
        /// 常にこのバイト列を返す
        case succeeding(Data)
        /// 常に失敗する
        case failing
        /// 指定回数だけ失敗し、その後は成功する
        case failingTimes(Int, then: Data)
    }

    struct FetchFailure: Error, Equatable {
        let reason: String
    }

    private let lock = NSLock()
    private var _behavior: Behavior
    private var _fetchedIds: [String] = []
    private var _uploaded: [(data: Data, contentType: String)] = []
    private var _deletedIds: [String] = []
    private var _uploadResultId = "uploaded-1"
    private var _attemptCount = 0

    init(behavior: Behavior = .succeeding(TestImage.pngData())) {
        self._behavior = behavior
    }

    /// 取得を要求された ID（実行順）
    var fetchedIds: [String] { lock.withLock { _fetchedIds } }
    /// アップロードされた内容（実行順）
    var uploaded: [(data: Data, contentType: String)] { lock.withLock { _uploaded } }
    /// 削除を要求された ID（実行順）
    var deletedIds: [String] { lock.withLock { _deletedIds } }

    var uploadResultId: String {
        get { lock.withLock { _uploadResultId } }
        set { lock.withLock { _uploadResultId = newValue } }
    }

    var behavior: Behavior {
        get { lock.withLock { _behavior } }
        set { lock.withLock { _behavior = newValue; _attemptCount = 0 } }
    }

    func fetch(id: String) async throws -> Data {
        try lock.withLock {
            _fetchedIds.append(id)
            _attemptCount += 1
            switch _behavior {
            case .succeeding(let data):
                return data
            case .failing:
                throw FetchFailure(reason: "fake transport is failing")
            case .failingTimes(let count, let data):
                if _attemptCount <= count {
                    throw FetchFailure(reason: "attempt \(_attemptCount) of \(count) fails")
                }
                return data
            }
        }
    }

    func upload(_ data: Data, contentType: String) async throws -> String {
        lock.withLock {
            _uploaded.append((data, contentType))
            return _uploadResultId
        }
    }

    func delete(id: String) async throws {
        lock.withLock { _deletedIds.append(id) }
    }
}

// MARK: - URL 経路のスタブ

/// `URLSession` の応答を差し替える。URL 直接指定の経路を実ネットワーク無しで確かめるために使う
final class StubURLProtocol: URLProtocol {
    private struct State {
        var responses: [String: (data: Data, statusCode: Int)] = [:]
        var requestedURLs: [String] = []
    }

    nonisolated(unsafe) private static var state = State()
    private static let lock = NSLock()

    static func stub(_ url: String, data: Data, statusCode: Int = 200) {
        lock.withLock { state.responses[url] = (data, statusCode) }
    }

    static func reset() {
        lock.withLock { state = State() }
    }

    static var requestedURLs: [String] {
        lock.withLock { state.requestedURLs }
    }

    /// このプロトコルだけを通すセッションを作る
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.url?.absoluteString ?? ""
        let stubbed = Self.lock.withLock { () -> (data: Data, statusCode: Int)? in
            Self.state.requestedURLs.append(key)
            return Self.state.responses[key]
        }

        guard let stubbed else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stubbed.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stubbed.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - 一時ディレクトリ

/// テストごとに独立したキャッシュディレクトリを配る
func makeTemporaryCacheDirectory(function: String = #function) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("CachedRemoteImageTests-\(UUID().uuidString)")
}
