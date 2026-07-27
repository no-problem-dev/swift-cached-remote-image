import APIClient
import Foundation
@testable import CachedRemoteImageAPIClient

/// `APIExecutable` のテストダブル。実行された契約のパスと本体を記録し、
/// スクリプトされた結果を返す。ネットワークには一切出ない
final class MockAPIClient: APIExecutable, @unchecked Sendable {
    enum MockError: Error { case unstubbed }

    /// 記録した 1 リクエスト
    struct Recorded {
        let path: String
        let contentType: String?
        let body: Data?
    }

    private let lock = NSLock()
    private var _recorded: [Recorded] = []
    private var _resourceProvider: ((String) throws -> ImageResourceDTO)?

    var recorded: [Recorded] { lock.withLock { _recorded } }
    var executedPaths: [String] { recorded.map(\.path) }

    /// `ImageResourceDTO` を出力とする契約への応答を登録する
    func stubResource(_ provider: @escaping (String) throws -> ImageResourceDTO) {
        lock.withLock { _resourceProvider = provider }
    }

    func executeWithResponse<E: APIContract>(_ contract: E) async throws -> APIResponse<E.Output>
        where E.Input == E, E: APIInput
    {
        let path = E.resolvePath(with: contract)
        let body = try contract.encodeBody(using: JSONEncoder())
        let provider = lock.withLock { () -> ((String) throws -> ImageResourceDTO)? in
            _recorded.append(
                Recorded(path: path, contentType: contract.additionalHeaders["Content-Type"], body: body)
            )
            return _resourceProvider
        }
        if let empty = EmptyOutput() as? E.Output {
            return APIResponse(output: empty, statusCode: 200, headers: [:])
        }
        guard let provider, let output = try provider(path) as? E.Output else {
            throw MockError.unstubbed
        }
        return APIResponse(output: output, statusCode: 200, headers: [:])
    }
}

/// 画像バイト列のダウンロードを差し替える
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
