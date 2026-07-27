import Foundation

/// ディスクキャッシュを置く場所。
///
/// アプリ本体とウィジェット拡張は**同じ値**からディレクトリを解決する。
/// 両者がパスを別々に組み立てると、綴りが 1 文字ずれただけでウィジェットが
/// 永久に無表示になる（アプリ側は正常に見えるので気づきにくい）。
/// 場所を値として渡せる形にしてあるのは、その食い違いを起こしようがなくするため。
public enum ImageCacheLocation: Sendable, Equatable {
    /// ユーザーの Caches ディレクトリ配下（既定）。
    ///
    /// OS が容量不足時に消せる場所。アプリ単体で使うぶんには妥当だが、
    /// ウィジェットからは読めないので、ウィジェットを持つなら ``appGroup(_:subdirectory:)`` を使う。
    case caches

    /// App Group コンテナ配下。
    ///
    /// ウィジェット拡張が読める唯一の場所。OS は勝手に消さないので、
    /// 上限は ``ImageLibraryConfiguration/diskCacheSizeLimit`` で自分で決める必要がある。
    ///
    /// - Parameters:
    ///   - identifier: App Group 識別子（`group.com.example.app` など）
    ///   - subdirectory: コンテナ内のサブディレクトリ名
    case appGroup(_ identifier: String, subdirectory: String = "CachedRemoteImage")

    /// 明示したディレクトリ。テストや、独自のファイル配置規約を持つアプリ向け。
    case directory(URL)

    /// 実際のディレクトリを解決し、無ければ作る。
    ///
    /// - Throws: App Group コンテナを解決できないとき ``ImageCacheLocationError/appGroupUnavailable(identifier:)``。
    ///   entitlement の付け忘れがここに出る。黙って別の場所に落とすと、
    ///   ウィジェットが何も出せない理由が最後まで分からなくなる
    func resolvedDirectory() throws -> URL {
        let directory: URL
        switch self {
        case .caches:
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                throw ImageCacheLocationError.cachesUnavailable
            }
            directory = caches.appendingPathComponent("CachedRemoteImage", isDirectory: true)
        case .appGroup(let identifier, let subdirectory):
            guard let container = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                throw ImageCacheLocationError.appGroupUnavailable(identifier: identifier)
            }
            directory = container.appendingPathComponent(subdirectory, isDirectory: true)
        case .directory(let url):
            directory = url
        }

        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}

/// ディスクキャッシュの置き場所を解決できなかった原因。
public enum ImageCacheLocationError: Error, Equatable, Sendable {
    /// App Group コンテナが取れなかった。entitlement か識別子の綴りを疑う
    case appGroupUnavailable(identifier: String)
    /// Caches ディレクトリが取れなかった
    case cachesUnavailable
}

extension ImageCacheLocationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable(let identifier):
            return "App Group '\(identifier)' のコンテナを解決できない（entitlement か識別子を確認する）"
        case .cachesUnavailable:
            return "Caches ディレクトリを解決できない"
        }
    }
}
